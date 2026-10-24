defmodule Jarvis.Planning do
  @moduledoc """
  Goals, their tasks, the widgets that make up their sections, comments on
  them, and the activity feed.

  Every function takes a `Jarvis.Scope` first: it confines reads and writes to
  the scope's project and attributes each change to the human or to an agent
  session. Every change is recorded as an event and broadcast to live viewers.
  """

  import Ecto.Query

  alias Jarvis.Planning.{Catalog, Comment, Event, Goal, Task, TaskType, Widget}
  alias Jarvis.Repo
  alias Jarvis.Scope
  alias Jarvis.Workspaces
  alias Jarvis.Workspaces.{AgentSession, Project}

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

  @doc "The goal with this number, with its tasks, widgets, and goal-level comments."
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

  @doc "The widgets of a goal (task `nil`) or of a task, in section and position order."
  def list_widgets(%Goal{} = goal, task) do
    owner_widgets(goal, task)
    |> order_by([w], [w.section, w.position, w.id])
    |> Repo.all()
  end

  @doc "A widget of the scope's project by id."
  def fetch_widget(%Scope{project: project}, id) do
    Repo.one(from w in Widget, where: w.id == ^id and w.project_id == ^project.id) |> found()
  end

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

  @doc "Changes the title of a goal."
  def update_goal(%Scope{} = scope, %Goal{} = goal, attrs) do
    changeset = Goal.changeset(goal, attrs)

    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(changeset) do
        if changeset.changes != %{},
          do: record!(scope, updated, nil, "#{ref(updated)}: renamed to #{updated.title}")

        {:ok, updated}
      end
    end)
    |> notify(scope)
  end

  ## Tasks

  @doc """
  Creates a task with the next free number in the goal, in the first step of
  its task type (`type`, default Feature).

  `attrs` takes `title`, `type`, and `claim: true` to claim it for the caller's
  worktree. A task an agent creates becomes that session's focus.
  """
  def create_task(%Scope{} = scope, %Goal{} = goal, attrs) do
    type_name = get(attrs, :type)
    type = if type_name in [nil, ""], do: :feature, else: TaskType.parse(type_name)

    Repo.transact(fn ->
      lock!(Goal, goal.id)
      number = next_number(from t in Task, where: t.goal_id == ^goal.id)

      changeset =
        %Task{goal_id: goal.id, project_id: goal.project_id, number: number}
        |> Task.create_changeset(attrs)
        |> put_type(type, type_name)
        |> put_claim(scope, attrs)

      with {:ok, task} <- Repo.insert(changeset) do
        task = %{task | goal: goal}

        record!(
          scope,
          goal,
          task,
          "created #{ref(task)} (#{TaskType.label(task.type)}): #{task.title}"
        )

        Workspaces.focus(scope, task.id)
        {:ok, task}
      end
    end)
    |> notify(scope)
  end

  defp put_type(changeset, nil, name) do
    Ecto.Changeset.add_error(
      changeset,
      :type,
      "unknown task type #{inspect(name)}; one of #{Enum.join(TaskType.keys(), ", ")}"
    )
  end

  defp put_type(changeset, type, _name) do
    changeset
    |> Ecto.Changeset.put_change(:type, type)
    |> Ecto.Changeset.put_change(:step, TaskType.first_step(type))
  end

  @doc """
  Changes a task. Fields absent from `attrs` are kept:

  - `title`
  - `claim`: `true` claims the task for the caller's worktree, `false` releases it
  - `transition`: moves the task along the named transition out of its current step
  - `force_step`: jumps straight to a step, ignoring the lifecycle (proof-of-concept runs)

  A task's type never changes. A task an agent changes becomes that session's focus.
  """
  def update_task(%Scope{} = scope, %Task{} = task, attrs) do
    task = Repo.preload(task, [:goal, :worktree])

    changeset =
      task
      |> Task.title_changeset(attrs)
      |> put_claim(scope, attrs)
      |> reject_type_change(task, attrs)
      |> put_move(scope, task, attrs)

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

  @doc "Moves a task along the named transition; see `update_task/3`."
  def move_task(scope, task, transition),
    do: update_task(scope, task, %{"transition" => transition})

  defp reject_type_change(changeset, task, attrs) do
    case get(attrs, :type) do
      nil ->
        changeset

      value ->
        if TaskType.parse(value) == task.type,
          do: changeset,
          else: Ecto.Changeset.add_error(changeset, :type, "a task's type never changes")
    end
  end

  defp put_move(changeset, scope, task, attrs) do
    case {get(attrs, :transition), get(attrs, :force_step)} do
      {nil, nil} ->
        changeset

      {name, nil} ->
        case check_transition(scope, task, name) do
          {:ok, transition} -> put_step(changeset, task, transition.to)
          {:error, reason} -> Ecto.Changeset.add_error(changeset, :transition, reason)
        end

      {nil, step} ->
        if TaskType.step?(task.type, step),
          do: put_step(changeset, task, step),
          else:
            Ecto.Changeset.add_error(
              changeset,
              :force_step,
              "no step #{inspect(step)}; steps: #{Enum.map_join(TaskType.steps(task.type), ", ", &elem(&1, 0))}"
            )

      _ ->
        Ecto.Changeset.add_error(
          changeset,
          :transition,
          "give transition or force_step, not both"
        )
    end
  end

  defp put_step(changeset, task, step) do
    changeset
    |> Ecto.Changeset.put_change(:step, step)
    |> Ecto.Changeset.put_change(:previous_step, task.step)
  end

  @doc """
  Whether the scope may move the task along the named transition now:
  `{:ok, transition}` or `{:error, reason}`.
  """
  def check_transition(scope, %Task{} = task, name) do
    case TaskType.find_transition(task.type, task.step, to_string(name)) do
      nil ->
        allowed = TaskType.transitions_from(task.type, task.step)

        {:error,
         "no transition #{inspect(name)} out of #{TaskType.step_label(task.type, task.step)}; " <>
           if(allowed == [],
             do: "this step has none",
             else: "allowed: " <> Enum.map_join(allowed, ", ", & &1.name)
           )}

      %{mover: :human} when scope.agent_session != nil ->
        {:error, "This transition is the human's decision"}

      transition ->
        case unmet_conditions(task, transition) do
          [] -> {:ok, transition}
          reasons -> {:error, Enum.join(reasons, "; ")}
        end
    end
  end

  @doc "Why the transition is not allowed yet, as human-readable reasons; `[]` when it is."
  def unmet_conditions(%Task{} = task, transition) do
    widgets = owner_widgets(task.goal_id, task) |> Repo.all()
    unmet_conditions(task, transition, widgets)
  end

  def unmet_conditions(_task, transition, widgets) do
    condition =
      case transition[:condition] do
        :requirements_confirmed ->
          case Enum.filter(widgets, &(&1.kind == "requirement")) do
            [] ->
              ["Write at least one requirement card first"]

            requirements ->
              case Enum.reject(requirements, & &1.human["confirmed"]) do
                [] -> []
                open -> ["#{Enum.map_join(open, ", ", & &1.data["id"])} not confirmed"]
              end
          end

        nil ->
          []
      end

    gates =
      for w <- widgets,
          w.kind == "quiz",
          w.data["mode"] == "gate",
          String.downcase(w.data["gates"] || "") == transition.name,
          open = Catalog.quiz_open_questions(w.data, w.human),
          open != [] do
        "quiz W#{w.id}: #{Enum.join(open, ", ")} not answered correctly"
      end

    condition ++ gates
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
    case get(attrs, :claim) do
      value when value in [true, "true"] -> true
      value when value in [false, "false"] -> false
      _ -> nil
    end
  end

  ## Widgets

  @doc """
  Applies an agent's widget operations to a goal (`task` nil) or a task, all or
  nothing. Each op is a map with `op`:

  - `add`: `section`, `kind`, `data`, optional `position` (1-based; default last)
  - `update`: `id`, `data` (replaces the data)
  - `move`: `id`, `position`, optional `section`
  - `delete`: `id`
  - `judge`: `id` (a quiz), `question`, `correct`, `explanation`

  Returns `{:ok, ids}` with the widget id each op touched, or
  `{:error, {:widgets, messages}}` naming the failing op and its fields.
  """
  def apply_widget_ops(%Scope{} = scope, %Goal{} = goal, task, ops) when is_list(ops) do
    ctx = %{scope: scope, goal: goal, task: task, sections: sections_of(task)}

    Repo.transact(fn ->
      ops
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {op, i}, {:ok, ids} ->
        case apply_op(ctx, op) do
          {:ok, id} ->
            {:cont, {:ok, [id | ids]}}

          {:error, messages} ->
            label = "op #{i} (#{(is_map(op) && op["op"]) || "?"})"
            {:halt, {:error, {:widgets, Enum.map(List.wrap(messages), &"#{label}: #{&1}")}}}
        end
      end)
      |> case do
        {:ok, ids} ->
          if ids != [] do
            record!(scope, goal, task, "#{ref(task || goal)}: #{length(ids)} widget change(s)")
          end

          if task, do: Workspaces.focus(scope, task.id)
          {:ok, Enum.reverse(ids)}

        error ->
          error
      end
    end)
    |> notify(scope)
  end

  def apply_widget_ops(_scope, _goal, _task, _ops),
    do: {:error, {:widgets, ["ops: must be a list of operations"]}}

  defp sections_of(nil), do: TaskType.sections(:goal)
  defp sections_of(%Task{type: type}), do: TaskType.sections(type)

  defp apply_op(ctx, %{"op" => "add"} = op) do
    with {:ok, section} <- resolve_section(ctx.sections, op["section"]),
         {:ok, kind} <- resolve_kind(op["kind"]),
         {:ok, data} <- Catalog.validate(kind, op["data"] || %{}) do
      widget =
        Repo.insert!(%Widget{
          project_id: ctx.goal.project_id,
          goal_id: ctx.goal.id,
          task_id: ctx.task && ctx.task.id,
          section: section,
          position: 0,
          kind: kind,
          data: data,
          human: %{}
        })

      place!(ctx, widget, section, op["position"])
      {:ok, widget.id}
    end
  end

  defp apply_op(ctx, %{"op" => "update"} = op) do
    with {:ok, widget} <- owned_widget(ctx, op["id"]),
         {:ok, data} <- Catalog.validate(widget.kind, op["data"] || %{}) do
      human = Catalog.reconcile(widget.kind, widget.data, data, widget.human)
      widget |> Ecto.Changeset.change(data: data, human: human) |> Repo.update!()
      note_update!(ctx, widget)
      {:ok, widget.id}
    end
  end

  defp apply_op(ctx, %{"op" => "move"} = op) do
    with {:ok, widget} <- owned_widget(ctx, op["id"]),
         {:ok, section} <- resolve_section(ctx.sections, op["section"] || widget.section) do
      old_section = widget.section
      widget = widget |> Ecto.Changeset.change(section: section) |> Repo.update!()
      if old_section != section, do: renumber!(ctx, old_section, nil)
      place!(ctx, widget, section, op["position"])
      note_update!(ctx, widget)
      {:ok, widget.id}
    end
  end

  defp apply_op(ctx, %{"op" => "delete"} = op) do
    with {:ok, widget} <- owned_widget(ctx, op["id"]) do
      Repo.delete!(widget)
      renumber!(ctx, widget.section, nil)
      {:ok, widget.id}
    end
  end

  defp apply_op(ctx, %{"op" => "judge"} = op) do
    with {:ok, widget} <- owned_widget(ctx, op["id"]),
         {:ok, human} <-
           wrap_error(
             Catalog.judge(widget, to_string(op["question"]), op["correct"], op["explanation"])
           ) do
      widget |> Ecto.Changeset.change(human: human) |> Repo.update!()
      {:ok, widget.id}
    end
  end

  defp apply_op(_ctx, _op), do: {:error, "op must be add, update, move, delete, or judge"}

  defp wrap_error({:error, message}), do: {:error, [message]}
  defp wrap_error(ok), do: ok

  defp resolve_section(sections, name) when is_binary(name) do
    wanted = name |> String.trim() |> String.downcase() |> String.replace(" ", "_")

    case Enum.find(sections, fn {key, label, _} ->
           key == wanted or String.downcase(label) == String.downcase(String.trim(name))
         end) do
      {key, _, _} ->
        {:ok, key}

      nil ->
        {:error, ["section: no section #{inspect(name)}; sections: #{section_list(sections)}"]}
    end
  end

  defp resolve_section(sections, _),
    do: {:error, ["section: required; sections: #{section_list(sections)}"]}

  defp section_list(sections), do: Enum.map_join(sections, ", ", &elem(&1, 0))

  defp resolve_kind(kind) do
    if Catalog.kind?(kind),
      do: {:ok, kind},
      else:
        {:error,
         ["kind: no widget kind #{inspect(kind)}; kinds: #{Enum.join(Catalog.kinds(), ", ")}"]}
  end

  defp owned_widget(ctx, id) do
    id = if is_binary(id), do: id |> String.trim_leading("W") |> Integer.parse(), else: {id, ""}

    with {id, ""} when is_integer(id) <- id,
         %Widget{} = widget <-
           Repo.one(from w in owner_widgets(ctx.goal, ctx.task), where: w.id == ^id) do
      {:ok, widget}
    else
      _ -> {:error, ["id: no widget #{inspect(id)} on #{ref(ctx.task || ctx.goal)}"]}
    end
  end

  # Puts the widget at a 1-based position of its section and renumbers the rest.
  defp place!(ctx, widget, section, position) do
    others =
      from(w in owner_widgets(ctx.goal, ctx.task),
        where: w.section == ^section and w.id != ^widget.id,
        order_by: [w.position, w.id],
        select: w.id
      )
      |> Repo.all()

    index =
      case position do
        p when is_integer(p) -> p |> max(1) |> min(length(others) + 1)
        _ -> length(others) + 1
      end

    renumber!(ctx, section, List.insert_at(others, index - 1, widget.id))
  end

  defp renumber!(ctx, section, nil) do
    ids =
      from(w in owner_widgets(ctx.goal, ctx.task),
        where: w.section == ^section,
        order_by: [w.position, w.id],
        select: w.id
      )
      |> Repo.all()

    renumber!(ctx, section, ids)
  end

  defp renumber!(_ctx, _section, ids) do
    for {id, i} <- Enum.with_index(ids, 1) do
      from(w in Widget, where: w.id == ^id) |> Repo.update_all(set: [position: i])
    end

    :ok
  end

  # A thread shows that the agent changed the widget it is about.
  defp note_update!(ctx, widget) do
    if Repo.exists?(from c in Comment, where: c.widget_id == ^widget.id and c.author != :system) do
      Repo.insert!(%Comment{
        goal_id: ctx.goal.id,
        task_id: ctx.task && ctx.task.id,
        widget_id: widget.id,
        author: :system,
        body: "Widget updated",
        anchor_label: anchor_label(widget, nil),
        anchor_text: Catalog.body_text(widget),
        agent_session_id: ctx.scope.agent_session && ctx.scope.agent_session.id
      })
    end
  end

  defp owner_widgets(%Goal{id: goal_id}, task), do: owner_widgets(goal_id, task)

  defp owner_widgets(goal_id, nil),
    do: from(w in Widget, where: w.goal_id == ^goal_id and is_nil(w.task_id))

  defp owner_widgets(_goal_id, %Task{id: task_id}),
    do: from(w in Widget, where: w.task_id == ^task_id)

  @doc """
  Applies what the human did with a widget (confirm a requirement, answer a
  quiz, re-weigh a criterion, mark a finding, a diagram that failed to render).
  What the listening session must hear becomes an anchored comment to deliver.
  """
  def widget_action(%Scope{} = scope, %Widget{} = widget, action, params) do
    with {:ok, human, notes} <- Catalog.human_action(widget, action, params) do
      Repo.transact(fn ->
        widget = widget |> Ecto.Changeset.change(human: human) |> Repo.update!()

        for {part, message} <- notes do
          author = if action == "render_error", do: :system, else: :human

          Repo.insert!(%Comment{
            goal_id: widget.goal_id,
            task_id: widget.task_id,
            widget_id: widget.id,
            part: part,
            author: author,
            body: message,
            anchor_label: anchor_label(widget, part),
            anchor_text: anchor_text(widget, part),
            deliver: true
          })
        end

        if action in ~w(confirm unconfirm) do
          verb = if action == "confirm", do: "confirmed", else: "unconfirmed"

          record!(
            scope,
            %Goal{id: widget.goal_id},
            widget.task_id && %Task{id: widget.task_id},
            "#{verb} #{widget.data["id"]}"
          )
        end

        {:ok, widget}
      end)
      |> notify(scope)
    end
  end

  ## Comments

  @doc """
  Adds a comment to a goal, or to one of its tasks when `task` is given.

  `attrs` may anchor it: `widget` (a widget id) and optionally `part`. A human
  comment with an anchor wakes the listening session. `reply_to` (a comment
  id) puts an agent's reply in the same thread as the comment it answers.
  """
  def add_comment(%Scope{} = scope, %Goal{} = goal, task, attrs) do
    base = %Comment{
      goal_id: goal.id,
      task_id: task && task.id,
      author: actor(scope),
      agent_session_id: scope.agent_session && scope.agent_session.id
    }

    Repo.transact(fn ->
      with {:ok, comment} <- anchor(base, goal, task, attrs),
           {:ok, comment} <- comment |> Comment.changeset(attrs) |> Repo.insert() do
        record!(scope, goal, task, "commented on #{ref(task || goal)}")
        {:ok, comment}
      end
    end)
    |> notify(scope)
  end

  defp anchor(comment, goal, task, attrs) do
    case {get(attrs, :reply_to), get(attrs, :widget)} do
      {nil, nil} ->
        {:ok, comment}

      {reply_to, _} when not is_nil(reply_to) ->
        case Repo.get(Comment, to_int(reply_to)) do
          %Comment{goal_id: goal_id} = parent when goal_id == goal.id ->
            {:ok,
             %{
               comment
               | reply_to_id: parent.id,
                 widget_id: parent.widget_id,
                 part: parent.part,
                 anchor_label: parent.anchor_label,
                 anchor_text: parent.anchor_text
             }}

          _ ->
            {:error, comment_error(:reply_to, "no comment #{inspect(reply_to)} on #{ref(goal)}")}
        end

      {nil, widget_id} ->
        part = get(attrs, :part)
        part = if part in [nil, ""], do: nil, else: to_string(part)

        widget =
          Repo.one(from w in owner_widgets(goal, task), where: w.id == ^to_int(widget_id))

        cond do
          is_nil(widget) ->
            {:error, comment_error(:widget, "no widget #{inspect(widget_id)} here")}

          part && is_nil(Catalog.part(widget, part)) ->
            {:error, comment_error(:part, "widget W#{widget.id} has no part #{inspect(part)}")}

          true ->
            {:ok,
             %{
               comment
               | widget_id: widget.id,
                 part: part,
                 anchor_label: anchor_label(widget, part),
                 anchor_text: anchor_text(widget, part),
                 deliver: comment.author == :human
             }}
        end
    end
  end

  defp comment_error(field, message) do
    %Comment{} |> Ecto.Changeset.change() |> Ecto.Changeset.add_error(field, message)
  end

  @doc "How an anchor is named in threads and messages, e.g. `Examples table W12 · Row 2`."
  def anchor_label(%Widget{} = widget, nil), do: "#{Catalog.label(widget.kind)} W#{widget.id}"

  def anchor_label(%Widget{} = widget, part) do
    case Catalog.part(widget, part) do
      {label, _} -> "#{Catalog.label(widget.kind)} W#{widget.id} · #{label}"
      nil -> "#{Catalog.label(widget.kind)} W#{widget.id} · #{part}"
    end
  end

  defp anchor_text(widget, nil), do: Catalog.body_text(widget)

  defp anchor_text(widget, part) do
    case Catalog.part(widget, part) do
      {_, text} -> text
      nil -> nil
    end
  end

  @doc """
  Returns the human's plain comments the agent session has not been shown yet,
  oldest first, and marks them shown. Anchored comments are delivered by
  `take_wake/1` instead.

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

        from(s in AgentSession, where: s.id == ^session.id)
        |> Repo.update_all(set: [inbox_cursor: cursor])
      end

      {:ok,
       Enum.filter(new, fn
         %Comment{author: author} when author != :human ->
           false

         %Comment{anchor_label: label} when not is_nil(label) ->
           false

         %Comment{task: nil} ->
           true

         %Comment{task: task} ->
           task.worktree_id in [nil, worktree.id] or task.id == session.task_id
       end)}
    end)
  end

  @doc """
  Takes the anchored comments waiting for this session: those whose listening
  session it is now. They are marked delivered and returned oldest first.
  """
  def take_wake(%Scope{agent_session: session, project: project}) do
    Repo.transact(fn ->
      pending =
        from(c in Comment,
          join: g in assoc(c, :goal),
          where: g.project_id == ^project.id and c.deliver and is_nil(c.delivered_at),
          order_by: c.id,
          preload: [goal: g, task: [:goal]]
        )
        |> Repo.all()

      mine =
        if pending == [] do
          []
        else
          sessions = live_sessions(project)
          Enum.filter(pending, &(listener_id(sessions, &1.goal, &1.task) == session.id))
        end

      if mine != [] do
        ids = Enum.map(mine, & &1.id)

        from(c in Comment, where: c.id in ^ids)
        |> Repo.update_all(set: [delivered_at: DateTime.utc_now()])
      end

      {:ok, mine}
    end)
  end

  @doc "The live session that hears anchored comments on the goal or task, or `nil`."
  def listening_session(%Project{} = project, %Goal{} = goal, task) do
    sessions = live_sessions(project)
    id = listener_id(sessions, goal, task)
    Enum.find(sessions, &(&1.id == id))
  end

  defp live_sessions(project) do
    now = DateTime.utc_now()

    project
    |> Workspaces.list_sessions()
    |> Enum.filter(&(AgentSession.presence(&1, now) in [:working, :idle]))
  end

  @doc """
  Picks the listening session among live sessions: for a task, the most
  recently active session focused on it, else in its claiming worktree; for a
  goal, the most recently active session focused on one of its tasks.
  """
  def listener_id(sessions, goal, task) do
    newest = fn candidates ->
      case Enum.max_by(candidates, & &1.last_seen_at, DateTime, fn -> nil end) do
        nil -> nil
        session -> session.id
      end
    end

    case task do
      %Task{} = task ->
        newest.(Enum.filter(sessions, &(&1.task_id == task.id))) ||
          (task.worktree_id &&
             newest.(Enum.filter(sessions, &(&1.worktree_id == task.worktree_id))))

      nil ->
        newest.(Enum.filter(sessions, &(&1.task && &1.task.goal_id == goal.id)))
    end
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

  # One readable line for the feed, e.g. "moved Design → Implementation; claimed".
  defp describe(%Ecto.Changeset{changes: changes, data: data}) do
    step =
      changes[:step] &&
        "moved #{TaskType.step_label(data.type, data.step)} → #{TaskType.step_label(data.type, changes.step)}"

    claim =
      case Map.fetch(changes, :worktree_id) do
        {:ok, nil} -> "released"
        {:ok, _} -> "claimed"
        :error -> nil
      end

    title = changes[:title] && "renamed"

    case Enum.reject([step, claim, title], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, "; ")
    end
  end

  @doc "How goals and tasks are referred to everywhere: `Goal 3`, `Task 3.2`."
  def ref(%Goal{number: n}), do: "Goal #{n}"
  def ref(%Task{number: n, goal: %Goal{number: g}}), do: "Task #{g}.#{n}"

  ## Helpers

  defp get(attrs, key), do: Map.get(attrs, Atom.to_string(key), Map.get(attrs, key))

  defp to_int(n) when is_integer(n), do: n

  defp to_int(n) when is_binary(n) do
    case Integer.parse(String.trim_leading(n, "W")) do
      {i, ""} -> i
      _ -> -1
    end
  end

  defp to_int(_), do: -1

  defp lock!(schema, id), do: Repo.one!(from r in schema, where: r.id == ^id, lock: "FOR UPDATE")

  defp next_number(query), do: (Repo.one(from r in query, select: max(r.number)) || 0) + 1

  defp notify({:ok, _} = result, scope) do
    Workspaces.broadcast_change(scope.project.id)
    result
  end

  defp notify(error, _scope), do: error
end
