defmodule Jarvis.Repo do
  use Ecto.Repo,
    otp_app: :jarvis,
    adapter: Ecto.Adapters.SQLite3

  # The database lives in the Data directory unless a config sets `:database`
  # (the tests do). Resolved here so every entry point (server, migrate, mix
  # tasks) agrees on the file.
  @impl true
  def init(_type, config) do
    {:ok, Keyword.put_new_lazy(config, :database, &Jarvis.DataDir.database_path/0)}
  end
end
