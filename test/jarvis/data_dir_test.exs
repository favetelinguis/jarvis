defmodule Jarvis.DataDirTest do
  use ExUnit.Case, async: false

  alias Jarvis.{DataDir, Fixtures, Planning}

  @home "/home/u"

  describe "resolve/3" do
    test "JARVIS_DATA_DIR wins" do
      env = %{"JARVIS_DATA_DIR" => "/tmp/j", "XDG_DATA_HOME" => "/data"}
      assert DataDir.resolve(env, {:unix, :linux}, @home) == "/tmp/j"
      assert DataDir.resolve(env, {:unix, :darwin}, @home) == "/tmp/j"
    end

    test "XDG_DATA_HOME on Linux" do
      assert DataDir.resolve(%{"XDG_DATA_HOME" => "/data"}, {:unix, :linux}, @home) ==
               "/data/jarvis"
    end

    test "the home default on Linux, with an empty variable counting as unset" do
      assert DataDir.resolve(%{}, {:unix, :linux}, @home) == "/home/u/.local/share/jarvis"

      assert DataDir.resolve(
               %{"JARVIS_DATA_DIR" => "", "XDG_DATA_HOME" => ""},
               {:unix, :linux},
               @home
             ) ==
               "/home/u/.local/share/jarvis"
    end

    test "Application Support on macOS" do
      assert DataDir.resolve(%{"XDG_DATA_HOME" => "/data"}, {:unix, :darwin}, @home) ==
               "/home/u/Library/Application Support/jarvis"
    end
  end

  describe "prepare/0" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp} do
      original = Application.get_env(:jarvis, Jarvis.Repo)
      on_exit(fn -> Application.put_env(:jarvis, Jarvis.Repo, original) end)

      point_repo_at = fn path ->
        Application.put_env(:jarvis, Jarvis.Repo, Keyword.put(original, :database, path))
      end

      {:ok, point_repo_at: point_repo_at, tmp: tmp}
    end

    test "creates a missing Data directory", %{point_repo_at: point, tmp: tmp} do
      point.(Path.join([tmp, "a", "b", "jarvis.db"]))
      assert DataDir.prepare() == :ok
      assert File.dir?(Path.join([tmp, "a", "b"]))
    end

    test "names the directory and the reason when it cannot be created", %{
      point_repo_at: point,
      tmp: tmp
    } do
      File.write!(Path.join(tmp, "file"), "")
      point.(Path.join([tmp, "file", "jarvis.db"]))

      assert {:error, message} = DataDir.prepare()
      assert message =~ Path.join(tmp, "file")
      refute File.exists?(Path.join([tmp, "file", "jarvis.db"]))
    end

    test "keeps one signing secret across calls", %{point_repo_at: point, tmp: tmp} do
      point.(Path.join(tmp, "jarvis.db"))
      assert :ok = DataDir.prepare()
      secret = DataDir.secret_key_base()
      assert byte_size(secret) >= 64
      assert DataDir.secret_key_base() == secret
    end
  end

  @tag :tmp_dir
  test "10 agent sessions write at the same moment without an error", %{tmp_dir: tmp} do
    name = :concurrent_repo
    start_supervised!({Jarvis.Repo, name: name, database: Path.join(tmp, "c.db"), pool_size: 10})
    Jarvis.Repo.put_dynamic_repo(name)
    {:ok, _, _} = Ecto.Migrator.with_repo(Jarvis.Repo, &Ecto.Migrator.run(&1, :up, all: true), [])
    repo = Fixtures.git_repo!()

    results =
      1..10
      |> Task.async_stream(
        fn n ->
          Jarvis.Repo.put_dynamic_repo(name)
          scope = Fixtures.agent_scope!(repo)
          Planning.create_goal(scope, %{"title" => "Goal #{n}"})
        end,
        max_concurrency: 10,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert results |> Enum.map(fn {:ok, g} -> g.number end) |> Enum.sort() == Enum.to_list(1..10)
  end
end
