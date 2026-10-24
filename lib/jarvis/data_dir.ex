defmodule Jarvis.DataDir do
  @moduledoc """
  The Data directory: where `jarvis.db` lives.

  `JARVIS_DATA_DIR` wins; otherwise `$XDG_DATA_HOME/jarvis` or `~/.local/share/jarvis`
  on Linux and `~/Library/Application Support/jarvis` on macOS. An empty variable
  counts as unset.
  """

  @doc "The Data directory for the given environment, OS, and home directory."
  def resolve(env \\ System.get_env(), os \\ :os.type(), home \\ System.user_home!()) do
    cond do
      set?(env["JARVIS_DATA_DIR"]) -> env["JARVIS_DATA_DIR"]
      match?({:unix, :darwin}, os) -> Path.join(home, "Library/Application Support/jarvis")
      set?(env["XDG_DATA_HOME"]) -> Path.join(env["XDG_DATA_HOME"], "jarvis")
      true -> Path.join(home, ".local/share/jarvis")
    end
  end

  def database_path, do: Path.join(resolve(), "jarvis.db")

  @doc "The signing secret, generated into the Data directory on first use."
  def secret_key_base do
    file = Path.join(Path.dirname(Jarvis.Repo.config()[:database]), "secret_key_base")

    case File.read(file) do
      {:ok, secret} when byte_size(secret) >= 64 ->
        secret

      _ ->
        secret = Base.encode64(:crypto.strong_rand_bytes(64))
        File.write!(file, secret)
        File.chmod!(file, 0o600)
        secret
    end
  end

  @doc """
  Creates the directory of the configured database and checks it is writable,
  before SQLite gets a chance to leave a file behind.
  """
  def prepare do
    database = Jarvis.Repo.config()[:database]
    dir = Path.dirname(database)
    probe = Path.join(dir, ".jarvis-write-test-#{System.unique_integer([:positive])}")

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(probe, ""),
         :ok <- File.rm(probe) do
      :ok
    else
      {:error, reason} ->
        {:error, "cannot use the Jarvis data directory #{dir}: #{:file.format_error(reason)}"}
    end
  end

  defp set?(value), do: value not in [nil, ""]
end
