defmodule Jarvis.IntegrationsTest do
  # Not async: the integrations settings are application-wide.
  use ExUnit.Case, async: false

  alias Jarvis.Integrations

  setup do
    original = Application.get_env(:jarvis, Integrations)
    home = Path.join(System.tmp_dir!(), "jarvis-int-#{System.unique_integer([:positive])}")
    File.mkdir_p!(home)
    Application.put_env(:jarvis, Integrations, Keyword.put(original, :home, home))

    on_exit(fn ->
      Application.put_env(:jarvis, Integrations, original)
      File.rm_rf!(home)
    end)

    {:ok, home: home, original: original}
  end

  defp put_cli(original, fun),
    do:
      Application.put_env(
        :jarvis,
        Integrations,
        Keyword.put(Application.get_env(:jarvis, Integrations), :cli, fun)
        |> then(fn c -> Keyword.merge(original, c) end)
      )

  test "pi: install adds the package once and keeps other settings; uninstall removes it", %{
    home: home
  } do
    path = Path.join(home, ".pi/agent/settings.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, ~s({"theme": "light", "packages": ["npm:other"]}))

    assert %{state: :not_installed, cli: {:ok, _}} = Integrations.status(:pi)
    assert %{state: :installed, error: nil} = Integrations.install(:pi)
    assert %{state: :installed} = Integrations.install(:pi)

    json = path |> File.read!() |> Jason.decode!()
    assert json["theme"] == "light"
    assert "npm:other" in json["packages"]
    assert Enum.count(json["packages"], &is_map/1) == 1

    assert %{"source" => source, "extensions" => ["extensions/jarvis.ts"]} =
             Enum.find(json["packages"], &is_map/1)

    assert String.ends_with?(source, "/pi")

    assert %{state: :not_installed} = Integrations.uninstall(:pi)
    assert path |> File.read!() |> Jason.decode!() |> Map.get("packages") == ["npm:other"]
  end

  test "pi: the old package entry is migrated without duplicates", %{home: home} do
    path = Path.join(home, ".pi/agent/settings.json")
    Integrations.install(:pi)
    json = path |> File.read!() |> Jason.decode!()
    source = Path.expand("../../pi", __DIR__)
    File.write!(path, Jason.encode!(Map.put(json, "packages", ["npm:other", source])))

    assert %{state: :partial} = Integrations.status(:pi)
    1..4 |> Task.async_stream(fn _ -> Integrations.install(:pi) end) |> Stream.run()
    assert %{state: :installed} = Integrations.status(:pi)

    assert ["npm:other", %{"source" => ^source}] =
             path |> File.read!() |> Jason.decode!() |> Map.fetch!("packages")

    installed = path |> File.read!() |> Jason.decode!()
    File.write!(path, Jason.encode!(Map.update!(installed, "packages", &(&1 ++ [source]))))
    assert %{state: :partial} = Integrations.status(:pi)
    assert %{state: :installed} = Integrations.install(:pi)
    assert length(path |> File.read!() |> Jason.decode!() |> Map.fetch!("packages")) == 2
  end

  test "pi: unreadable configuration is also untouched by uninstall", %{home: home} do
    path = Path.join(home, ".pi/agent/settings.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "{ nope")
    assert %{state: :unreadable, error: error} = Integrations.uninstall(:pi)
    assert error =~ path
    assert File.read!(path) == "{ nope"
  end

  test "pi: write failures are reported without a successful installation", %{home: home} do
    File.write!(Path.join(home, ".pi"), "not a directory")
    assert %{error: error} = Integrations.install(:pi)
    assert is_binary(error)
    assert File.read!(Path.join(home, ".pi")) == "not a directory"
  end

  test "pi: shared skills remain while another agent is installed", %{home: home} do
    Integrations.install(:pi)
    Integrations.install(:codex)
    # Shared skills still count as a present entry under the existing health definition.
    assert %{state: :partial, error: nil} = Integrations.uninstall(:pi)
    settings = home |> Path.join(".pi/agent/settings.json") |> File.read!() |> Jason.decode!()
    assert settings["packages"] == []
    assert File.exists?(Path.join(home, ".agents/skills/specify/SKILL.md"))
    assert %{state: :installed} = Integrations.status(:codex)
  end

  test "codex: install and uninstall leave the rest of config.toml byte for byte", %{home: home} do
    path = Path.join(home, ".codex/config.toml")
    File.mkdir_p!(Path.dirname(path))
    original = "model = \"x\"\n# my comment\n[projects.\"/a\"]\ntrust_level = \"trusted\"\n"
    File.write!(path, original)

    assert %{state: :installed} = Integrations.install(:codex)
    installed = File.read!(path)
    assert String.starts_with?(installed, original)
    assert installed =~ "[mcp_servers.jarvis]"
    assert installed =~ "UserPromptSubmit"

    assert %{state: :installed} = Integrations.install(:codex)
    assert File.read!(path) == installed

    assert %{state: :not_installed} = Integrations.uninstall(:codex)
    assert File.read!(path) == original
  end

  test "codex: the old mirror hook is removed on install", %{home: home} do
    path = Path.join(home, ".codex/config.toml")
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    model = "x"

    [[hooks.Stop]]
    [[hooks.Stop.hooks]]
    type = "command"
    command = "curl -fsS http://localhost:4000/api/transcripts/sync?harness=codex || true"
    timeout = 10

    [[hooks.Stop]]
    [[hooks.Stop.hooks]]
    type = "command"
    command = "my-own-hook"
    """)

    Integrations.install(:codex)
    text = File.read!(path)
    refute text =~ "transcripts/sync"
    assert text =~ "my-own-hook"
    assert text =~ ~s(model = "x")
  end

  test "copilot: tools in mcp-config.json and hooks in settings.json", %{home: home} do
    settings = Path.join(home, ".copilot/settings.json")
    File.mkdir_p!(Path.dirname(settings))

    File.write!(
      settings,
      ~s({"hooks": {"agentStop": [{"type": "command", "bash": "mine"}]}, "x": 1})
    )

    assert %{state: :installed} = Integrations.install(:copilot)
    json = settings |> File.read!() |> Jason.decode!()
    assert length(json["hooks"]["agentStop"]) == 2
    assert json["x"] == 1
    mcp = home |> Path.join(".copilot/mcp-config.json") |> File.read!() |> Jason.decode!()
    assert mcp["mcpServers"]["jarvis"]["command"] == "node"

    assert %{state: :not_installed} = Integrations.uninstall(:copilot)
    json = settings |> File.read!() |> Jason.decode!()
    assert json["hooks"] == %{"agentStop" => [%{"type" => "command", "bash" => "mine"}]}
  end

  test "copilot: migration replaces the ignored prompt hook and preserves unrelated hooks", %{
    home: home
  } do
    settings = Path.join(home, ".copilot/settings.json")
    Integrations.install(:copilot)
    json = settings |> File.read!() |> Jason.decode!()
    old = hd(json["hooks"]["userPromptTransformed"])

    legacy =
      json
      |> put_in(["hooks", "userPromptSubmitted"], [old, %{"bash" => "mine"}])
      |> put_in(["hooks", "notification"], [])

    File.write!(settings, Jason.encode!(legacy))
    Integrations.install(:copilot)
    hooks = settings |> File.read!() |> Jason.decode!() |> Map.fetch!("hooks")
    assert hooks["userPromptSubmitted"] == [%{"bash" => "mine"}]
    assert length(hooks["userPromptTransformed"]) == 1
    assert hooks["notification"] == []
    Integrations.uninstall(:copilot)
    remaining = settings |> File.read!() |> Jason.decode!() |> Map.fetch!("hooks")
    assert remaining == %{"userPromptSubmitted" => [%{"bash" => "mine"}], "notification" => []}
  end

  test "an unparseable configuration is Unreadable, named, and untouched", %{home: home} do
    path = Path.join(home, ".pi/agent/settings.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "{ nope")

    assert %{state: :unreadable, error: error} = Integrations.status(:pi)
    assert error =~ path
    assert %{state: :unreadable} = Integrations.install(:pi)
    assert File.read!(path) == "{ nope"
  end

  test "install is refused while the CLI is not found", %{original: original} do
    put_cli(original, fn _ -> :not_found end)
    assert %{cli: :not_found, state: :not_installed, error: error} = Integrations.install(:pi)
    assert error =~ "not found"
  end

  test "skills are shared: one copy, kept until the last agent is uninstalled", %{home: home} do
    skill = Path.join(home, ".agents/skills/design/SKILL.md")
    Integrations.install(:codex)
    assert File.exists?(skill)
    assert length(Path.wildcard(Path.join(home, ".agents/skills/*/SKILL.md"))) == 10
    refute File.read!(skill) |> String.contains?("$ARGUMENTS")

    assert %{state: :installed} = Integrations.install(:copilot)
    Integrations.uninstall(:codex)
    assert File.exists?(skill)
    assert %{state: :installed} = Integrations.status(:copilot)

    Integrations.uninstall(:copilot)
    refute File.exists?(skill)
  end

  test "stale skills show as partly installed and install brings them up to date", %{home: home} do
    Integrations.install(:pi)
    skill = Path.join(home, ".agents/skills/poc/SKILL.md")
    File.write!(skill, "old")
    assert %{state: :partial} = Integrations.status(:pi)
    assert %{state: :installed} = Integrations.install(:pi)
    assert File.read!(skill) != "old"
  end

  test "a skill the human wrote is never overwritten", %{home: home} do
    mine = Path.join(home, ".agents/skills/design")
    File.mkdir_p!(mine)
    File.write!(Path.join(mine, "SKILL.md"), "mine")

    assert %{state: state, error: error} = Integrations.install(:codex)
    assert state == :not_installed
    assert error =~ "design"
    assert File.read!(Path.join(mine, "SKILL.md")) == "mine"
  end

  test "concurrent installs leave each entry once", %{home: home} do
    1..6 |> Task.async_stream(fn _ -> Integrations.install(:codex) end) |> Stream.run()
    text = File.read!(Path.join(home, ".codex/config.toml"))
    assert length(String.split(text, "[mcp_servers.jarvis]")) == 2
  end
end
