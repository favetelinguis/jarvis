defmodule Jarvis.Fixtures do
  @moduledoc "Git repositories, agent scopes, goals, and tasks for tests."

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Jarvis.{Planning, Scope, Workspaces}

  @doc "A fresh git repository on branch `main` in a temp dir, removed after the test."
  def git_repo! do
    dir = Path.join(System.tmp_dir!(), "jarvis-repo-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    git!(dir, ~w(init -q -b main))
    git!(dir, ~w(-c user.email=t@t -c user.name=t commit -q --allow-empty -m init))
    dir
  end

  @doc "Adds a worktree of `repo` on a new branch and returns its path."
  def worktree!(repo, branch) do
    path = repo <> "-" <> branch
    on_exit(fn -> File.rm_rf!(path) end)
    git!(repo, ["worktree", "add", "-q", "-b", branch, path])
    path
  end

  defp git!(dir, args), do: {_, 0} = System.cmd("git", ["-C", dir | args])

  @doc "The scope of an agent session working in `cwd`."
  def agent_scope!(cwd, session_id \\ "session-#{System.unique_integer([:positive])}") do
    {:ok, scope} = Workspaces.register(%{"cwd" => cwd, "session_id" => session_id})
    scope
  end

  def human_scope(%Scope{project: project}), do: Scope.for_human(project)

  def goal!(scope, attrs \\ %{}) do
    {:ok, goal} = Planning.create_goal(scope, Enum.into(attrs, %{"title" => "A goal"}))
    goal
  end

  def task!(scope, goal, attrs \\ %{}) do
    {:ok, task} = Planning.create_task(scope, goal, Enum.into(attrs, %{"title" => "A task"}))
    task
  end
end
