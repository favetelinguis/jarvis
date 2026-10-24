defmodule Jarvis.Integrations do
  @moduledoc """
  Installs, removes, and reports Jarvis in the user-level configuration of the
  coding agents (pi, Codex, Copilot CLI).

  An integration is a list of *entries*: the pi package, an MCP tools server, presence
  hooks, the workflow skills. The state of an agent is always read from its
  configuration files at that moment (`:installed`, `:partial`, `:not_installed`,
  or `:unreadable`), never remembered. Install and uninstall add and remove only
  Jarvis entries: TOML is edited by inserting and cutting marked blocks, so the rest
  of the file stays byte for byte; JSON files are parsed and written back.

  Settings (`config :jarvis, Jarvis.Integrations`): `:home`, `:root` (this repository),
  `:url` (the server the agents report to), `:cli` (a function returning
  `{:ok, version}` or `:not_found` for an agent, for tests).
  """

  @type agent :: :pi | :codex | :copilot
  @type state :: :installed | :partial | :not_installed | :unreadable
  @type status :: %{
          agent: agent(),
          label: String.t(),
          cli: {:ok, String.t()} | :not_found,
          state: state(),
          error: String.t() | nil
        }

  @agents [pi: "pi", codex: "Codex", copilot: "Copilot CLI"]
  @entries %{
    pi: [:package, :skills],
    codex: [:tools, :presence, :skills],
    copilot: [:tools, :presence, :skills]
  }
  @marker ".jarvis-managed"
  @default_root Path.expand("../..", __DIR__)

  @doc "The status of every agent, CLIs probed in parallel."
  @spec list() :: [status()]
  def list do
    Keyword.keys(@agents)
    |> Task.async_stream(&status/1, timeout: 10_000, ordered: true)
    |> Enum.map(fn {:ok, status} -> status end)
  end

  @doc "Reads the CLI and the configuration of `agent` now."
  @spec status(agent(), String.t() | nil) :: status()
  def status(agent, error \\ nil) do
    {state, read_error} =
      case entry_states(agent) do
        {:ok, states} -> {summarize(Map.values(states)), nil}
        {:error, message} -> {:unreadable, message}
      end

    %{
      agent: agent,
      label: Keyword.fetch!(@agents, agent),
      cli: cli(agent),
      state: state,
      error: error || read_error
    }
  end

  @doc "Adds every Jarvis entry of `agent` that is missing or out of date."
  @spec install(agent()) :: status()
  def install(agent) do
    locked(agent, fn ->
      with :ok <- require_cli(agent),
           {:ok, states} <- entry_states(agent),
           :ok <- check_skill_conflicts(agent, states),
           :ok <- strip_old_mirror_hook(agent),
           :ok <- each_entry(@entries[agent], states, &add(agent, &1)) do
        status(agent)
      else
        {:error, message} -> status(agent, message)
      end
    end)
  end

  @doc "Removes every Jarvis entry of `agent`. Shared skills stay while another agent uses them."
  @spec uninstall(agent()) :: status()
  def uninstall(agent) do
    locked(agent, fn ->
      keep_skills = Enum.any?(Keyword.keys(@agents) -- [agent], &uses_skills?/1)
      entries = if keep_skills, do: List.delete(@entries[agent], :skills), else: @entries[agent]

      with {:ok, _} <- entry_states(agent),
           :ok <- strip_old_mirror_hook(agent),
           :ok <- each_entry(entries, nil, &remove(agent, &1)) do
        status(agent)
      else
        {:error, message} -> status(agent, message)
      end
    end)
  end

  # Two Install clicks at once (two tabs) take turns, so each entry exists once.
  defp locked(agent, fun) do
    :global.trans({__MODULE__, self()}, fn -> guarded(agent, fun) end, [node()])
  end

  defp guarded(agent, fun) do
    fun.()
  rescue
    error in [File.Error, File.CopyError] -> status(agent, Exception.message(error))
  end

  defp require_cli(agent) do
    case cli(agent) do
      {:ok, _} -> :ok
      :not_found -> {:error, "#{Keyword.fetch!(@agents, agent)} CLI not found"}
    end
  end

  defp each_entry(entries, states, fun) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      if states && states[entry] == :present do
        {:cont, :ok}
      else
        case fun.(entry) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end
      end
    end)
  end

  defp summarize(states) do
    present = Enum.count(states, &(&1 == :present))

    cond do
      present == length(states) -> :installed
      present == 0 -> :not_installed
      true -> :partial
    end
  end

  # Another agent keeps the shared skills while any of its own entries exist.
  defp uses_skills?(agent) do
    case entry_states(agent) do
      {:ok, states} -> Enum.any?(states, fn {entry, s} -> entry != :skills and s == :present end)
      {:error, _} -> true
    end
  end

  defp entry_states(agent) do
    Enum.reduce_while(@entries[agent], {:ok, %{}}, fn entry, {:ok, acc} ->
      case present?(agent, entry) do
        {:ok, present?} ->
          {:cont, {:ok, Map.put(acc, entry, if(present?, do: :present, else: :missing))}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end)
  end

  ## CLI

  defp cli(agent) do
    case config(:cli) do
      nil -> probe_cli(agent)
      fun -> fun.(agent)
    end
  end

  defp probe_cli(agent) do
    name = if agent == :pi, do: "pi", else: Atom.to_string(agent)

    with path when is_binary(path) <- System.find_executable(name),
         {:ok, version} <- version(path) do
      {:ok, version}
    else
      _ -> :not_found
    end
  end

  defp version(path) do
    task = Task.async(fn -> System.cmd(path, ["--version"], stderr_to_stdout: true) end)

    case Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {out, 0}} ->
        {:ok, out |> String.split("\n", trim: true) |> List.first("") |> String.trim()}

      _ ->
        {:ok, "version unknown"}
    end
  end

  ## Entries: present?/2, add/2, remove/2

  # Per entry: is it in the configuration, add it, remove it. pi: package in settings.json;
  # Codex: marked blocks in config.toml; Copilot CLI: mcp-config.json and hooks in
  # settings.json; skills: the nine workflows in ~/.agents/skills, shared by all agents.
  defp present?(:pi, :package) do
    with {:ok, json} <- read_json(pi_settings()) do
      {:ok, Enum.any?(json["packages"] || [], &(package_source(&1) == pi_package()))}
    end
  end

  defp present?(:codex, :tools), do: block_present?(codex_config(), "tools", codex_tools_block())

  defp present?(:codex, :presence),
    do: block_present?(codex_config(), "presence", codex_presence_block())

  defp present?(:copilot, :tools) do
    with {:ok, json} <- read_json(copilot_mcp()) do
      {:ok, get_in(json, ["mcpServers", "jarvis"]) == copilot_server()}
    end
  end

  defp present?(:copilot, :presence) do
    with {:ok, json} <- read_json(copilot_settings()) do
      hooks = json["hooks"] || %{}

      {:ok, Enum.all?(copilot_hooks(), fn {event, hook} -> hook in List.wrap(hooks[event]) end)}
    end
  end

  defp present?(_agent, :skills) do
    {:ok, Enum.all?(skill_names(), &skill_current?/1)}
  end

  defp add(:pi, :package) do
    update_json(pi_settings(), fn json ->
      Map.update(json, "packages", [pi_package()], &(&1 ++ [pi_package()]))
    end)
  end

  defp add(:codex, :tools), do: put_block(codex_config(), "tools", codex_tools_block())
  defp add(:codex, :presence), do: put_block(codex_config(), "presence", codex_presence_block())

  defp add(:copilot, :tools) do
    update_json(copilot_mcp(), fn json ->
      Map.update(
        json,
        "mcpServers",
        %{"jarvis" => copilot_server()},
        &Map.put(&1, "jarvis", copilot_server())
      )
    end)
  end

  defp add(:copilot, :presence) do
    update_json(copilot_settings(), fn json ->
      hooks =
        Enum.reduce(copilot_hooks(), json["hooks"] || %{}, fn {event, hook}, hooks ->
          Map.put(hooks, event, without_jarvis(hooks[event]) ++ [hook])
        end)

      Map.put(json, "hooks", hooks)
    end)
  end

  defp add(_agent, :skills) do
    Enum.each(skill_names(), fn name ->
      dest = skill_dir(name)
      File.rm_rf!(dest)
      File.mkdir_p!(Path.dirname(dest))
      File.cp_r!(Path.join(skills_source(), name), dest)
      File.write!(Path.join(dest, @marker), "Installed by Jarvis; Uninstall removes it.\n")
    end)

    :ok
  end

  defp remove(:pi, :package) do
    update_json(pi_settings(), fn json ->
      case json["packages"] do
        nil ->
          json

        packages ->
          Map.put(json, "packages", Enum.reject(packages, &(package_source(&1) == pi_package())))
      end
    end)
  end

  # Codex: marked blocks in ~/.codex/config.toml
  defp remove(:codex, :tools), do: cut_block(codex_config(), "tools")
  defp remove(:codex, :presence), do: cut_block(codex_config(), "presence")

  # Copilot CLI: ~/.copilot/mcp-config.json and the hooks in ~/.copilot/settings.json
  defp remove(:copilot, :tools) do
    update_json(copilot_mcp(), fn json ->
      case json["mcpServers"] do
        %{} = servers -> Map.put(json, "mcpServers", Map.delete(servers, "jarvis"))
        _ -> json
      end
    end)
  end

  defp remove(:copilot, :presence) do
    update_json(copilot_settings(), fn json ->
      case json["hooks"] do
        %{} = hooks ->
          hooks =
            Enum.reduce(copilot_hooks(), hooks, fn {event, _}, hooks ->
              case without_jarvis(hooks[event]) do
                [] -> Map.delete(hooks, event)
                rest -> Map.put(hooks, event, rest)
              end
            end)

          Map.put(json, "hooks", hooks)

        _ ->
          json
      end
    end)
  end

  # The nine workflow skills, shared by all agents in ~/.agents/skills.
  defp remove(_agent, :skills) do
    for name <- skill_names(), File.exists?(Path.join(skill_dir(name), @marker)) do
      File.rm_rf!(skill_dir(name))
    end

    :ok
  end

  defp without_jarvis(hooks),
    do:
      Enum.reject(
        List.wrap(hooks),
        &(is_map(&1) and String.contains?(&1["bash"] || "", "jarvis-hook.mjs"))
      )

  defp package_source(%{"source" => source}), do: source
  defp package_source(source), do: source

  ## Skills

  defp skills_source, do: Path.join(root(), "skills")

  defp skill_names do
    skills_source()
    |> File.ls!()
    |> Enum.filter(&File.dir?(Path.join(skills_source(), &1)))
    |> Enum.sort()
  end

  defp skill_dir(name), do: Path.join([home(), ".agents", "skills", name])

  defp skill_current?(name) do
    dest = skill_dir(name)

    File.exists?(Path.join(dest, @marker)) and
      Enum.all?(Path.wildcard(Path.join([skills_source(), name, "**", "*"])), fn src ->
        File.dir?(src) or
          File.read(Path.join(dest, Path.relative_to(src, Path.join(skills_source(), name)))) ==
            File.read(src)
      end)
  end

  # Install never overwrites a skill of the same name that Jarvis did not install.
  defp check_skill_conflicts(agent, states) do
    if :skills in @entries[agent] and states[:skills] != :present do
      conflicts =
        Enum.filter(skill_names(), fn name ->
          File.exists?(skill_dir(name)) and not File.exists?(Path.join(skill_dir(name), @marker))
        end)

      case conflicts do
        [] ->
          :ok

        names ->
          {:error, "Skill #{Enum.join(names, ", ")} exists and is not Jarvis's; not overwritten"}
      end
    else
      :ok
    end
  end

  ## Files

  defp read_json(path) do
    case File.read(path) do
      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, "#{path}: #{:file.format_error(reason)}"}

      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{} = json} -> {:ok, json}
          {:ok, _} -> {:error, "#{path}: not a JSON object"}
          {:error, error} -> {:error, "#{path}: #{Exception.message(error)}"}
        end
    end
  end

  defp update_json(path, fun) do
    with {:ok, json} <- read_json(path),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, [Jason.encode_to_iodata!(fun.(json), pretty: true), "\n"]) do
      :ok
    else
      {:error, reason} when is_atom(reason) -> {:error, "#{path}: #{:file.format_error(reason)}"}
      {:error, _} = error -> error
    end
  end

  defp read_text(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, :enoent} -> {:ok, ""}
      {:error, reason} -> {:error, "#{path}: #{:file.format_error(reason)}"}
    end
  end

  defp block_re(name),
    do: ~r/\n?# >>> jarvis #{name}\b.*?# <<< jarvis #{name}\n/s

  defp block_present?(path, name, block) do
    with {:ok, text} <- read_text(path) do
      case Regex.run(block_re(name), text) do
        [found] ->
          {:ok, String.trim(found) == String.trim(block)}

        nil ->
          if(String.contains?(text, "# >>> jarvis #{name}"),
            do: {:error, "#{path}: unbalanced Jarvis block"},
            else: {:ok, false}
          )
      end
    end
  end

  defp put_block(path, name, block) do
    with {:ok, text} <- read_text(path),
         text = Regex.replace(block_re(name), text, ""),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      sep = if text == "" or String.ends_with?(text, "\n"), do: "", else: "\n"
      File.write(path, [text, sep, if(text == "", do: "", else: "\n"), block])
    end
  end

  defp cut_block(path, name) do
    with {:ok, text} <- read_text(path) do
      if text == "", do: :ok, else: File.write(path, Regex.replace(block_re(name), text, ""))
    end
  end

  # The mirror hook that old READMEs had the human append to Codex's config;
  # its endpoint no longer exists.
  defp strip_old_mirror_hook(:codex) do
    with {:ok, text} <- read_text(codex_config()) do
      stripped = remove_old_mirror_hook(text)
      if stripped == text, do: :ok, else: File.write(codex_config(), stripped)
    end
  end

  defp strip_old_mirror_hook(_agent), do: :ok

  defp remove_old_mirror_hook(text) do
    Regex.replace(
      ~r/\[\[hooks\.(Stop|SessionEnd)\]\]\n\[\[hooks\.\1\.hooks\]\]\n(?:(?!\[\[?)[^\n]*\n)*?command = "[^\n]*api\/transcripts\/sync[^\n]*"\n(?:(?!\[\[?)[^\n]*\n)*/,
      text,
      ""
    )
  end

  ## Definitions of the entries

  defp codex_tools_block do
    """
    # >>> jarvis tools (managed by Jarvis, removed by Uninstall)
    [mcp_servers.jarvis]
    command = "node"
    args = [#{json(bridge())}, "codex"]
    env = { JARVIS_URL = #{json(url())} }
    # <<< jarvis tools
    """
  end

  defp codex_presence_block do
    hooks =
      for {event, arg} <- [{"UserPromptSubmit", "start"}, {"Stop", "stop"}, {"SessionEnd", "end"}] do
        """
        [[hooks.#{event}]]
        [[hooks.#{event}.hooks]]
        type = "command"
        command = #{json(hook_command("codex", arg))}
        timeout = 10
        """
      end

    "# >>> jarvis presence (managed by Jarvis, removed by Uninstall)\n" <>
      Enum.join(hooks, "\n") <> "# <<< jarvis presence\n"
  end

  defp copilot_server do
    %{
      "type" => "local",
      "command" => "node",
      "args" => [bridge(), "copilot"],
      "env" => %{"JARVIS_URL" => url()},
      "tools" => ["*"]
    }
  end

  defp copilot_hooks do
    for {event, arg} <- [
          {"userPromptSubmitted", "start"},
          {"agentStop", "stop"},
          {"sessionEnd", "end"}
        ] do
      {event, %{"type" => "command", "bash" => hook_command("copilot", arg), "timeoutSec" => 10}}
    end
  end

  defp hook_command(agent, arg),
    do: "JARVIS_URL=#{shell(url())} node #{shell(hook_script())} #{agent} #{arg}"

  defp shell(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
  defp json(value), do: Jason.encode!(value)

  ## Paths and settings

  defp config(key), do: :jarvis |> Application.get_env(__MODULE__, []) |> Keyword.get(key)
  defp home, do: config(:home) || System.user_home!()
  defp root, do: config(:root) || @default_root
  defp url, do: config(:url) || JarvisWeb.Endpoint.url()
  defp bridge, do: Path.join([root(), "agent", "jarvis-mcp.mjs"])
  defp hook_script, do: Path.join([root(), "agent", "jarvis-hook.mjs"])
  defp pi_package, do: Path.join(root(), "pi")
  defp pi_settings, do: Path.join([home(), ".pi", "agent", "settings.json"])
  defp codex_config, do: Path.join([home(), ".codex", "config.toml"])
  defp copilot_mcp, do: Path.join([home(), ".copilot", "mcp-config.json"])
  defp copilot_settings, do: Path.join([home(), ".copilot", "settings.json"])
end
