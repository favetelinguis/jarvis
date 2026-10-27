defmodule Jarvis.Integrations.Subagents do
  @moduledoc """
  The custom subagents Jarvis installs for pi, Codex, and Copilot CLI, so the
  workflows can name the agent they want (`jarvis-scout`, `jarvis-design-reviewer`,
  `jarvis-impl-reviewer`) instead of the harness's default subagent.

  Each definition is one file in `subagents/` (a description, the tools per harness,
  and the instructions) and is rendered into the format of the harness. The human
  sets a model and an effort per subagent and harness; an empty value leaves the
  field out, so the subagent inherits the session's. Settings are not stored
  anywhere else: they are read back from the installed files. Until a file exists, the
  settings are the defaults below.

  Maps of settings are `%{subagent_name => %{"model" => String.t(), "effort" => String.t()}}`.
  """

  @type definition :: %{
          name: String.t(),
          description: String.t(),
          tools: %{pi: String.t(), copilot: String.t()},
          instructions: String.t()
        }
  @type settings :: %{String.t() => %{String.t() => String.t()}}

  @blank %{"model" => "", "effort" => ""}
  # The scout is cheap and quick; the reviewers get the stronger model and more effort.
  @defaults %{
    pi: %{
      scout: {"openrouter/openai/gpt-6-luna", "low"},
      reviewer: {"openrouter/anthropic/claude-opus-5.5", "high"}
    },
    codex: %{scout: {"gpt-5.6-luna", "low"}, reviewer: {"gpt-5.6-terra", "high"}},
    copilot: %{scout: {"gpt-6-luna", "low"}, reviewer: {"claude-opus-5.5", "high"}}
  }
  @efforts %{
    pi: ~w(off minimal low medium high xhigh max),
    codex: ~w(minimal low medium high xhigh),
    copilot: ~w(low medium high xhigh)
  }
  # A model id as the harnesses write it, e.g. `openai/gpt-6:high`; it is written into
  # YAML and TOML unquoted, so nothing else may pass.
  @model ~r/\A[A-Za-z0-9][A-Za-z0-9._\/:@+-]{0,99}\z/

  @doc "The efforts `agent` accepts."
  @spec efforts(atom()) :: [String.t()]
  def efforts(agent), do: Map.fetch!(@efforts, agent)

  @doc "The definitions in `root/subagents`, sorted by name."
  @spec definitions(Path.t()) :: [definition()]
  def definitions(root) do
    for path <- Enum.sort(Path.wildcard(Path.join([root, "subagents", "*.md"]))) do
      [_, header, body] = String.split(File.read!(path), "---\n", parts: 3)
      fields = Map.new(Regex.scan(~r/^([\w-]+): (.*)$/m, header), fn [_, k, v] -> {k, v} end)

      %{
        name: Path.basename(path, ".md"),
        description: fields["description"],
        tools: %{pi: fields["pi-tools"], copilot: fields["copilot-tools"]},
        instructions: String.trim(body)
      }
    end
  end

  @doc "Where `agent` keeps the subagent `name`."
  @spec path(Path.t(), atom(), String.t()) :: Path.t()
  def path(home, :pi, name), do: Path.join([home, ".pi", "agent", "agents", name <> ".md"])
  def path(home, :codex, name), do: Path.join([home, ".codex", "agents", name <> ".toml"])
  def path(home, :copilot, name), do: Path.join([home, ".copilot", "agents", name <> ".agent.md"])

  @doc "The model and effort in the installed files; the defaults for a missing or unreadable file."
  @spec read(Path.t(), atom(), [definition()]) :: settings()
  def read(home, agent, definitions) do
    Map.new(definitions, fn %{name: name} ->
      case File.read(path(home, agent, name)) do
        {:ok, text} -> {name, parse(agent, text)}
        {:error, _} -> {name, default(agent, name)}
      end
    end)
  end

  defp default(agent, name) do
    role = if name == "jarvis-scout", do: :scout, else: :reviewer
    {model, effort} = @defaults[agent][role]
    %{"model" => model, "effort" => effort}
  end

  @doc """
  The settings to install: what is installed now, with `given` (from the form) on top.
  Unknown subagents are ignored; an invalid model or effort is an error naming it.
  """
  @spec resolve(atom(), [definition()], settings(), map()) ::
          {:ok, settings()} | {:error, String.t()}
  def resolve(agent, definitions, current, given) do
    Enum.reduce_while(definitions, {:ok, %{}}, fn %{name: name}, {:ok, acc} ->
      entry = Map.merge(Map.get(current, name, @blank), form_values(given[name]))

      case validate(agent, name, entry) do
        :ok -> {:cont, {:ok, Map.put(acc, name, entry)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc "Whether every installed file is exactly what `settings` renders."
  @spec current?(Path.t(), atom(), [definition()], settings()) :: boolean()
  def current?(home, agent, definitions, settings) do
    Enum.all?(definitions, fn %{name: name} = definition ->
      File.read(path(home, agent, name)) == {:ok, render(agent, definition, settings[name])}
    end)
  end

  @doc "Writes (or rewrites) every subagent file of `agent`."
  @spec write(Path.t(), atom(), [definition()], settings()) :: :ok | {:error, String.t()}
  def write(home, agent, definitions, settings) do
    Enum.reduce_while(definitions, :ok, fn %{name: name} = definition, :ok ->
      file = path(home, agent, name)

      with :ok <- File.mkdir_p(Path.dirname(file)),
           :ok <- File.write(file, render(agent, definition, settings[name])) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, "#{file}: #{:file.format_error(reason)}"}}
      end
    end)
  end

  @doc "Deletes the subagent files of `agent`."
  @spec remove(Path.t(), atom(), [definition()]) :: :ok
  def remove(home, agent, definitions) do
    for %{name: name} <- definitions, do: File.rm(path(home, agent, name))
    :ok
  end

  @doc "The file for `agent`: the definition in the harness's format, with the model and effort."
  @spec render(atom(), definition(), map()) :: String.t()
  def render(:pi, d, s) do
    markdown(
      [
        {"name", d.name},
        {"description", d.description},
        {"tools", d.tools.pi},
        {"model", s["model"]},
        {"thinking", s["effort"]},
        {"inheritProjectContext", "true"}
      ],
      d.instructions
    )
  end

  def render(:copilot, d, s) do
    tools = d.tools.copilot |> String.split(", ") |> Jason.encode!()

    markdown(
      [
        {"name", d.name},
        {"description", d.description},
        {"tools", tools},
        {"model", s["model"]},
        {"reasoning-effort", s["effort"]},
        {"include-custom-instructions", "true"}
      ],
      d.instructions
    )
  end

  # Codex has no tool list in an agent file: it inherits the session's permissions.
  def render(:codex, d, s) do
    fields = [
      {"name", Jason.encode!(d.name)},
      {"description", Jason.encode!(d.description)},
      {"model", s["model"] != "" && Jason.encode!(s["model"])},
      {"model_reasoning_effort", s["effort"] != "" && Jason.encode!(s["effort"])}
    ]

    lines = for {key, value} <- fields, value, do: "#{key} = #{value}\n"
    IO.iodata_to_binary([lines, "\ndeveloper_instructions = '''\n", d.instructions, "\n'''\n"])
  end

  defp markdown(fields, body) do
    lines = for {key, value} <- fields, value != "", do: "#{key}: #{value}\n"
    IO.iodata_to_binary(["---\n", lines, "---\n\n", body, "\n"])
  end

  defp parse(:codex, text) do
    header = text |> String.split("\ndeveloper_instructions", parts: 2) |> hd()
    values(header, ~r/^model = "([^"]*)"$/m, ~r/^model_reasoning_effort = "([^"]*)"$/m)
  end

  defp parse(agent, text) do
    header = text |> String.split("---\n", parts: 3) |> Enum.at(1, "")
    effort = if agent == :pi, do: "thinking", else: "reasoning-effort"
    values(header, ~r/^model: (\S+)$/m, ~r/^#{effort}: (\S+)$/m)
  end

  defp values(header, model, effort) do
    %{"model" => capture(header, model), "effort" => capture(header, effort)}
  end

  defp capture(text, regex) do
    case Regex.run(regex, text) do
      [_, value] -> value
      nil -> ""
    end
  end

  defp form_values(%{} = values) do
    for {key, value} <- values, key in ["model", "effort"], is_binary(value), into: %{} do
      {key, String.trim(value)}
    end
  end

  defp form_values(_), do: %{}

  defp validate(agent, name, %{"model" => model, "effort" => effort}) do
    cond do
      model != "" and not Regex.match?(@model, model) ->
        {:error, "#{name}: #{inspect(model)} is not a model id"}

      effort != "" and effort not in efforts(agent) ->
        {:error, "#{name}: effort must be one of #{Enum.join(efforts(agent), ", ")}"}

      true ->
        :ok
    end
  end
end
