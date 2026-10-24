defmodule Jarvis.Planning do
  @moduledoc """
  Goals, their tasks, comments on them, and the activity feed.

  Every function takes a `Jarvis.Scope` first: it confines reads and writes to
  the scope's project and attributes each change to the human or to an agent
  session. Every change is recorded as an event and broadcast to live viewers.
  """

  import Ecto.Query

  alias Jarvis.Planning.{Comment, Event, Goal, Task}
  alias Jarvis.Repo
  alias Jarvis.Scope
  alias Jarvis.Workspaces
  alias Jarvis.Workspaces.Project

  ## Reads

  @doc "The project's goals in number order, each with its tasks and their worktrees."
  def list_goals(%Scope{project: project}) do
    from(g in Goal,
      where: g.project_id == ^project.id,
      order_by: g.number,
      preload: [tasks: :worktree]
    )
    |> Repo.all()
  end

  @doc "The goal with this number, with its tasks and goal-level comments."
  def fetch_goal(%Scope{project: project}, number) do
    goal_comments = from(c in Comment, where: is_nil(c.task_id), order_by: c.id)

    from(g in Goal,
      where: g.project_id == ^project.id and g.number == ^number,
      preload: [tasks: :worktree, comments: ^{goal_comments, [:agent_session]}]
    )
    |> Repo.one()
    |> found()
  end

  @doc "The task with this number in the goal with this number, with its goal, worktree, and comments."
  def fetch_task(%Scope{project: project}, goal_number, task_number) do
    from(t in Task,
      join: g in assoc(t, :goal),
      where:
        g.project_id == ^project.id and g.number == ^goal_number and t.number == ^task_number,
      preload: [:goal, :worktree, comments: :agent_session]
    )
    |> Repo.one()
    |> found()
  end

  defp found(nil), do: {:error, :not_found}
  defp found(record), do: {:ok, record}

  @doc "The newest events of the project, newest first."
  def list_events(%Scope{project: project}, limit \\ 50) do
    from(e in Event,
      where: e.project_id == ^project.id,
      order_by: [desc: e.id],
      limit: ^limit,
      preload: [:agent_session]
    )
    |> Repo.all()
  end

  ## Goals

  @doc "Creates a goal with the next free number in the project."
  def create_goal(%Scope{project: project} = scope, attrs) do
    Repo.transact(fn ->
      lock!(Project, project.id)
      number = next_number(from g in Goal, where: g.project_id == ^project.id)

      with {:ok, goal} <-
             %Goal{project_id: project.id, number: number}
             |> Goal.changeset(attrs)
             |> Repo.insert() do
        record!(scope, goal, nil, "created #{ref(goal)}: #{goal.title}")
        {:ok, goal}
      end
    end)
    |> notify(scope)
  end

  @doc "Changes the given fields of a goal; fields absent from `attrs` are kept."
  def update_goal(%Scope{} = scope, %Goal{} = goal, attrs) do
    changeset = Goal.changeset(goal, attrs)

    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(changeset) do
        if summary = describe(changeset),
          do: record!(scope, updated, nil, "#{ref(updated)}: #{summary}")

        {:ok, updated}
      end
    end)
    |> notify(scope)
  end

  ## Tasks

  @doc """
  Creates a task with the next free number in the goal.

  `attrs` takes the task fields, plus `claim: true` to claim it for the
  caller's worktree. A task an agent creates becomes that session's focus.
  """
  def create_task(%Scope{} = scope, %Goal{} = goal, attrs) do
    Repo.transact(fn ->
      lock!(Goal, goal.id)
      number = next_number(from t in Task, where: t.goal_id == ^goal.id)

      changeset =
        %Task{goal_id: goal.id, project_id: goal.project_id, number: number}
        |> Task.changeset(attrs)
        |> put_claim(scope, attrs)

      with {:ok, task} <- Repo.insert(changeset) do
        task = %{task | goal: goal}
        record!(scope, goal, task, "created #{ref(task)}: #{task.title}")
        Workspaces.focus(scope, task.id)
        {:ok, task}
      end
    end)
    |> notify(scope)
  end

  @doc """
  Changes the given fields of a task; fields absent from `attrs` are kept.

  `claim: true` claims the task for the caller's worktree, `claim: false`
  releases it. A task an agent changes becomes that session's focus.
  """
  def update_task(%Scope{} = scope, %Task{} = task, attrs) do
    task = Repo.preload(task, [:goal, :worktree])
    changeset = task |> Task.changeset(attrs) |> put_claim(scope, attrs)

    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(changeset) do
        if summary = describe(changeset) do
          record!(scope, task.goal, updated, "#{ref(updated)}: #{summary}")
        end

        Workspaces.focus(scope, task.id)
        {:ok, Repo.preload(updated, :worktree, force: true)}
      end
    end)
    |> notify(scope)
  end

  defp put_claim(changeset, scope, attrs) do
    case claim(attrs) do
      true when is_nil(scope.worktree) ->
        Ecto.Changeset.add_error(
          changeset,
          :claim,
          "only an agent in a worktree can claim a task"
        )

      true ->
        Ecto.Changeset.put_change(changeset, :worktree_id, scope.worktree.id)

      false ->
        Ecto.Changeset.put_change(changeset, :worktree_id, nil)

      nil ->
        changeset
    end
  end

  defp claim(attrs) do
    case Map.get(attrs, "claim", Map.get(attrs, :claim)) do
      value when value in [true, "true"] -> true
      value when value in [false, "false"] -> false
      _ -> nil
    end
  end

  ## Comments

  @doc "Adds a comment to a goal, or to one of its tasks when `task` is given."
  def add_comment(%Scope{} = scope, %Goal{} = goal, task, attrs) do
    comment = %Comment{
      goal_id: goal.id,
      task_id: task && task.id,
      author: actor(scope),
      agent_session_id: scope.agent_session && scope.agent_session.id
    }

    Repo.transact(fn ->
      with {:ok, comment} <- comment |> Comment.changeset(attrs) |> Repo.insert() do
        record!(scope, goal, task, "commented on #{ref(task || goal)}")
        {:ok, comment}
      end
    end)
    |> notify(scope)
  end

  @doc """
  Returns the human comments the agent session has not been shown yet, oldest
  first, and marks them shown.

  A session is shown comments on goals, on unclaimed tasks, on tasks its
  worktree claimed, and on its focus task; comments on tasks other worktrees
  claimed go to those worktrees' sessions.
  """
  def take_inbox(%Scope{agent_session: session, worktree: worktree, project: project}) do
    Repo.transact(fn ->
      new =
        from(c in Comment,
          join: g in assoc(c, :goal),
          left_join: t in assoc(c, :task),
          where: g.project_id == ^project.id and c.id > ^session.inbox_cursor,
          order_by: c.id,
          preload: [goal: g, task: t]
        )
        |> Repo.all()

      if new != [] do
        cursor = new |> Enum.map(& &1.id) |> Enum.max()

        from(s in Jarvis.Workspaces.AgentSession, where: s.id == ^session.id)
        |> Repo.update_all(set: [inbox_cursor: cursor])
      end

      {:ok,
       Enum.filter(new, fn
         %Comment{author: :agent} ->
           false

         %Comment{task: nil} ->
           true

         %Comment{task: task} ->
           task.worktree_id in [nil, worktree.id] or task.id == session.task_id
       end)}
    end)
  end

  ## Events

  defp record!(scope, goal, task, summary) do
    Repo.insert!(%Event{
      project_id: scope.project.id,
      goal_id: goal && goal.id,
      task_id: task && task.id,
      agent_session_id: scope.agent_session && scope.agent_session.id,
      actor: actor(scope),
      summary: summary
    })
  end

  defp actor(scope), do: if(Scope.agent?(scope), do: :agent, else: :human)

  # One readable line for the feed, e.g. "moved todo → ready; claimed; updated sketch, tests".
  defp describe(%Ecto.Changeset{changes: changes, data: data}) do
    status = changes[:status] && "moved #{data.status} → #{changes.status}"

    claim =
      case Map.fetch(changes, :worktree_id) do
        {:ok, nil} -> "released"
        {:ok, _} -> "claimed"
        :error -> nil
      end

    edited =
      changes
      |> Map.drop([:status, :worktree_id])
      |> Map.keys()
      |> Enum.map(&(&1 |> Atom.to_string() |> String.replace("_", " ")))

    edited = if edited != [], do: "updated " <> Enum.join(edited, ", ")

    case Enum.reject([status, claim, edited], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, "; ")
    end
  end

  @doc "How goals and tasks are referred to everywhere: `Goal 3`, `Task 3.2`."
  def ref(%Goal{number: n}), do: "Goal #{n}"
  def ref(%Task{number: n, goal: %Goal{number: g}}), do: "Task #{g}.#{n}"

  ## Helpers

  defp lock!(schema, id), do: Repo.one!(from r in schema, where: r.id == ^id, lock: "FOR UPDATE")

  defp next_number(query), do: (Repo.one(from r in query, select: max(r.number)) || 0) + 1

  defp notify({:ok, _} = result, scope) do
    Workspaces.broadcast_change(scope.project.id)
    result
  end

  defp notify(error, _scope), do: error
end
