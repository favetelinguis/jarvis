ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Jarvis.Repo, :manual)

# Integrations write into a home directory: never the real one, and no real CLIs.
Application.put_env(:jarvis, Jarvis.Integrations,
  home: Path.join(System.tmp_dir!(), "jarvis-test-home-#{System.unique_integer([:positive])}"),
  cli: fn agent -> {:ok, "#{agent} 1.0.0"} end
)
