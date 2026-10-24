defmodule Jarvis.Release do
  @moduledoc """
  What the `jarvis` command runs inside a Release (see `rel/overlays/bin/jarvis`).
  """

  @app :jarvis

  def version do
    Application.load(@app)
    IO.puts(Application.spec(@app, :vsn))
  end

  @doc "Applies every pending migration and prints how many were applied."
  def migrate do
    Application.load(@app)

    with {:error, message} <- Jarvis.DataDir.prepare() do
      IO.puts(:stderr, "jarvis: " <> message)
      System.halt(1)
    end

    {:ok, applied, _} =
      Ecto.Migrator.with_repo(Jarvis.Repo, &Ecto.Migrator.run(&1, :up, all: true))

    IO.puts("applied #{length(applied)} migration(s)")
  rescue
    error ->
      IO.puts(:stderr, "jarvis: migration failed: " <> Exception.message(error))
      System.halt(1)
  end
end
