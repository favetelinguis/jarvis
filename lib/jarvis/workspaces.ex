defmodule Jarvis.Workspaces do
  @moduledoc """
  Projects, their worktrees, and the agent sessions working in them.

  Agents never create these explicitly: every API request carries the caller's
  git and pi identity, and `register/1` upserts it. That is what lets many
  sessions across many worktrees find and share the same project's tasks.
  """

  import Ecto.Query
  import Ecto.Changeset

  alias Jarvis.Repo
  alias Jarvis.Scope
  alias Jarvis.Workspaces.{AgentSession, Git, Project, Worktree}

  @pubsub Jarvis.PubSub

  ## PubSub

  @doc "Subscribes to change notifications for one project, or for the project list with `:all`."
  def subscribe(:all), do: Phoenix.PubSub.subscribe(@pubsub, "projects")
  def subscribe(project_id), do: Phoenix.PubSub.subscribe(@pubsub, "project:#{project_id}")

  @doc "Tells every viewer of the project, and of the project list, that something changed."
  def broadcast_change(project_id) do
    Phoenix.PubSub.broadcast(@pubsub, "project:#{project_id}", {:jarvis, :changed})
    Phoenix.PubSub.broadcast(@pubsub, "projects", {:jarvis, :changed})
  end

  ## Registration

  @identity_types %{cwd: :string, session_id: :string, session_name: :string}

  @doc """
  Upserts the caller's project, worktree, and agent session and returns their scope.

  The project and worktree are resolved from `cwd` with git. A new session
  starts with an inbox cursor at the newest comment, so it is not flooded with
  comments made before it existed.
  """
  def register(params) do
    changeset =
      {%{}, @identity_types}
      |> cast(params, Map.keys(@identity_types))
      |> validate_required([:cwd, :session_id])
      |> validate_length(:cwd, max: 4096)
      |> validate_length(:session_id, max: 255)
      |> validate_length(:session_name, max: 255)

    with {:ok, id} <- apply_action(changeset, :register),
         {:ok, {project, worktree}} <- locate(id.cwd) do
      {:ok,
       %Scope{
         project: project,
         worktree: worktree,
         agent_session: upsert_session(project, worktree, id)
       }}
    end
  end

  @doc "Upserts the project and worktree that the directory `cwd` belongs to."
  def locate(cwd) do
    with {:ok, location} <- Git.resolve(cwd) do
      project =
        Repo.insert!(
          %Project{key: location.project_key, name: location.project_name},
          on_conflict: {:replace, [:updated_at]},
          conflict_target: :key,
          returning: true
        )

      worktree =
        Repo.insert!(
          %Worktree{
            project_id: project.id,
            path: location.worktree_path,
            name: Path.basename(location.worktree_path),
            branch: location.branch
          },
          on_conflict: {:replace, [:branch, :project_id, :updated_at]},
          conflict_target: :path,
          returning: true
        )

      {:ok, {project, worktree}}
    end
  end

  defp upsert_session(project, worktree, id) do
    newest_comment = Repo.one(from c in "comments", select: max(c.id)) || 0

    Repo.insert!(
      %AgentSession{
        pi_session_id: id.session_id,
        name: id[:session_name],
        project_id: project.id,
        worktree_id: worktree.id,
        last_seen_at: DateTime.utc_now(),
        inbox_cursor: newest_comment
      },
      on_conflict: {:replace, [:name, :project_id, :worktree_id, :last_seen_at, :updated_at]},
      conflict_target: :pi_session_id,
      returning: true
    )
  end

  @doc "Records what the agent session is doing now: `:idle`, `:working`, or `:ended`."
  def set_state(%Scope{agent_session: %AgentSession{} = session} = scope, state)
      when state in [:idle, :working, :ended] do
    session = session |> change(state: state) |> Repo.update!()
    broadcast_change(scope.project.id)
    %{scope | agent_session: session}
  end

  @doc "Makes `task_id` the agent session's focus, shown next to the task in the UI."
  def focus(%Scope{agent_session: nil}, _task_id), do: :ok

  def focus(%Scope{agent_session: session}, task_id) do
    from(s in AgentSession, where: s.id == ^session.id)
    |> Repo.update_all(set: [task_id: task_id])

    :ok
  end

  ## Queries

  def get_project!(id), do: Repo.get!(Project, id)

  @doc "All projects, most recently active first, with task counts and live session counts."
  def list_projects do
    task_counts =
      from(t in Jarvis.Planning.Task,
        group_by: [t.project_id, t.status],
        select: {t.project_id, t.status, count(t.id)}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), fn {_, status, n} -> {status, n} end)
      |> Map.new(fn {id, counts} -> {id, Map.new(counts)} end)

    now = DateTime.utc_now()

    live_sessions =
      from(s in AgentSession, where: s.state != :ended)
      |> Repo.all()
      |> Enum.filter(&(AgentSession.presence(&1, now) in [:idle, :working]))
      |> Enum.frequencies_by(& &1.project_id)

    from(p in Project, order_by: [desc: p.updated_at])
    |> Repo.all()
    |> Enum.map(fn project ->
      %{
        project: project,
        counts: Map.get(task_counts, project.id, %{}),
        live_sessions: Map.get(live_sessions, project.id, 0)
      }
    end)
  end

  @doc "The project's sessions seen in the last day, newest first, with worktree and focus task."
  def list_sessions(%Project{id: project_id}) do
    since = DateTime.add(DateTime.utc_now(), -1, :day)

    from(s in AgentSession,
      where: s.project_id == ^project_id and s.last_seen_at > ^since,
      order_by: [desc: s.last_seen_at],
      preload: [:worktree, task: :goal]
    )
    |> Repo.all()
  end
end
