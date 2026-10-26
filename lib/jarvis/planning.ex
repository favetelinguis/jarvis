defmodule Jarvis.Planning do
  @moduledoc """
  Goals, their tasks, the widgets that make up their sections, comments on
  them, and the activity feed.

  Every function takes a `Jarvis.Scope` first: it confines reads and writes to
  the scope's project and attributes each change to the human or to an agent
  session. Every change is recorded as an event and broadcast to live viewers.
  """

  import Ecto.Query

  alias Jarvis.Planning.{Catalog, Comment, Event, Goal, Report, Task, TaskType, Widget}
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

  @doc """
  Changes the title or POC status of a goal. An agent may set POC status but
  never clear it: only the human says a goal has been reviewed.
  """
  def update_goal(%Scope{} = scope, %Goal{} = goal, attrs) do
    changeset = goal |> Goal.changeset(attrs) |> guard_poc(scope)

    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(changeset) do
        if Map.has_key?(changeset.changes, :title),
          do: record!(scope, updated, nil, "#{ref(updated)}: renamed to #{updated.title}")

        case changeset.changes do
          %{poc: true} -> record!(scope, updated, nil, "#{ref(updated)}: marked POC")
          %{poc: false} -> record!(scope, updated, nil, "#{ref(updated)}: POC status cleared")
          _ -> :ok
        end

        {:ok, updated}
      end
    end)
    |> notify(scope)
  end

  defp guard_poc(changeset, scope) do
    if Scope.agent?(scope) and Ecto.Changeset.get_change(changeset, :poc) == false,
      do: Ecto.Changeset.add_error(changeset, :poc, "only the human can clear POC status"),
      else: changeset
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

        report!(scope, goal, nil, %{
          "action" => "task_created",
          "task" => task.number,
          "title" => task.title,
          "reasons" => List.wrap(attrs |> get(:reason) |> blank_to_nil())
        })

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
  - `transition`: moves the task along the named transition out of its current
    step; `comment` says what to change (required where the transition says
    so) and `new_title` names the task a `spec issue` splits off
  - `force_step`: jumps straight to a step, ignoring the lifecycle (POC goals only)
  - `handoff`: `true` gives the turn to the human without leaving the step

  A move the human makes is delivered to the listening session. A task's type
  never changes. A task an agent changes becomes that session's focus.
  `reason` and `needs` go into the agent's turn report.
  """
  def update_task(%Scope{} = scope, %Task{} = task, attrs) do
    task = Repo.preload(task, [:goal, :worktree])
    move = plan_move(scope, task, attrs)

    changeset =
      task
      |> Task.title_changeset(attrs)
      |> put_claim(scope, attrs)
      |> reject_type_change(task, attrs)
      |> put_move(task, move)
      |> put_handoff(scope, task, attrs)

    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(changeset),
           {:ok, _} <- after_move(scope, task, %{updated | goal: task.goal}, move, attrs) do
        if summary = describe(changeset, move) do
          record!(scope, task.goal, updated, "#{ref(updated)}: #{summary}")
        end

        if needs = attrs |> get(:needs) |> blank_to_nil(),
          do: put_needs!(scope, task.goal, task, needs)

        Workspaces.focus(scope, task.id)
        {:ok, Repo.preload(updated, :worktree, force: true)}
      end
    end)
    |> notify(scope)
  end

  @doc "Moves a task along the named transition; see `update_task/3`."
  def move_task(scope, task, transition, attrs \\ %{}),
    do: update_task(scope, task, Map.put(attrs, "transition", transition))

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

  # What the call asks for: nil, {:transition, t}, {:force, step}, or {:error, field, message}.
  defp plan_move(scope, task, attrs) do
    case {get(attrs, :transition), get(attrs, :force_step)} do
      {nil, nil} ->
        nil

      {name, nil} ->
        with {:ok, t} <- check_transition(scope, task, name),
             :ok <- check_move_comment(t, attrs) do
          {:transition, t}
        else
          {:error, field, reason} -> {:error, field, reason}
          {:error, reason} -> {:error, :transition, reason}
        end

      {nil, step} ->
        cond do
          not poc_goal?(task) ->
            {:error, :force_step,
             "force_step is only for POC goals; mark the goal POC with /poc, or move with a transition"}

          TaskType.step?(task.type, step) ->
            {:force, step}

          true ->
            {:error, :force_step,
             "no step #{inspect(step)}; steps: #{Enum.map_join(TaskType.steps(task.type), ", ", &elem(&1, 0))}"}
        end

      _ ->
        {:error, :transition, "give transition or force_step, not both"}
    end
  end

  defp poc_goal?(%Task{goal_id: id}),
    do: Repo.one!(from g in Goal, where: g.id == ^id, select: g.poc)

  defp check_move_comment(t, attrs) do
    cond do
      t[:comment] && blank?(get(attrs, :comment)) ->
        {:error, :comment, "\"#{t.name}\" needs a comment that says what to change"}

      t[:creates_task] && blank?(get(attrs, :new_title)) ->
        {:error, :new_title, "\"#{t.name}\" needs a title for the new task"}

      true ->
        :ok
    end
  end

  defp blank?(value), do: value in [nil, ""] or (is_binary(value) and String.trim(value) == "")

  defp put_move(changeset, _task, nil), do: changeset

  defp put_move(changeset, _task, {:error, field, reason}),
    do: Ecto.Changeset.add_error(changeset, field, reason)

  defp put_move(changeset, task, {:force, step}), do: put_step(changeset, task, step)

  # Sending work back without leaving the step gives the turn to the agent;
  # a spec issue sends the work to a new task instead.
  defp put_move(changeset, _task, {:transition, %{from: step, to: step} = t}) do
    if t[:comment] && !t[:creates_task],
      do: Ecto.Changeset.put_change(changeset, :turn, :agent),
      else: changeset
  end

  defp put_move(changeset, task, {:transition, t}), do: put_step(changeset, task, t.to)

  defp put_step(changeset, task, step) do
    changeset
    |> Ecto.Changeset.put_change(:step, step)
    |> Ecto.Changeset.put_change(:previous_step, task.step)
    |> Ecto.Changeset.force_change(:turn, nil)
    |> then(&if step == "quiz", do: Ecto.Changeset.put_change(&1, :quiz_skipped, false), else: &1)
  end

  defp put_handoff(changeset, scope, task, attrs) do
    if get(attrs, :handoff) in [true, "true"] do
      case check_handoff(scope, task) do
        :ok -> Ecto.Changeset.put_change(changeset, :turn, :human)
        {:error, reason} -> Ecto.Changeset.add_error(changeset, :handoff, reason)
      end
    else
      changeset
    end
  end

  @doc """
  Whether the scope may hand the task's step over to the human now: only an
  agent, only in a step that is handed over, only while it is the agent's turn,
  and Design only with a review report.
  """
  def check_handoff(scope, %Task{} = task) do
    steps = TaskType.handoff_steps(task.type)
    labels = Enum.map_join(steps, ", ", &TaskType.step_label(task.type, &1))

    cond do
      not Scope.agent?(scope) ->
        {:error, "only an agent hands a step over"}

      task.step not in steps or turn(task) == :human ->
        {:error,
         "#{TaskType.step_label(task.type, task.step)} cannot be handed over now" <>
           if(turn(task) == :human, do: " (it is already the human's turn)", else: "") <>
           "; steps that are handed over: #{labels}"}

      task.type == :feature and task.step == "design" and
          not Enum.any?(task_widgets(task), &(&1.section == "review" and &1.kind == "findings")) ->
        {:error,
         "the review report is missing: run a review in a fresh context and write it as a findings widget in the review section first"}

      true ->
        :ok
    end
  end

  defp task_widgets(task), do: owner_widgets(task.goal_id, task) |> Repo.all()

  @doc """
  Whose turn it is in the task: `:human`, `{:agent, command}` (command may be
  nil), or `:none`.
  """
  def turn(%Task{} = task) do
    case {task.turn, TaskType.start_turn(task.type, task.step)} do
      {:human, _} -> :human
      {_, {:agent, command, _}} when task.turn in [nil, :agent] -> {:agent, command}
      {:agent, _} -> {:agent, agent_command(task)}
      {nil, other} -> other
    end
  end

  defp agent_command(task) do
    Enum.find_value(TaskType.transitions_from(task.type, task.step), & &1[:command])
  end

  # The move's effects beyond the task row: the message to the listening
  # session, a split-off task, what becomes out of date, the turn report.
  defp after_move(scope, task, updated, {:transition, %{mover: :human} = t}, attrs) do
    if Scope.agent?(scope), do: raise("an agent made a human transition")
    comment = get(attrs, :comment)

    Repo.insert!(%Comment{
      goal_id: task.goal_id,
      task_id: task.id,
      author: :human,
      body: if(blank?(comment), do: "", else: String.trim(comment)),
      transition: t.name,
      to_step: updated.step,
      deliver: true
    })

    if t.name == "dig deeper" do
      stale = Enum.filter(task_widgets(task), &(&1.section == "recommendation"))
      mark_stale!(scope, task.goal, task, stale, "you asked to dig deeper", nil)
    end

    if t[:creates_task],
      do: split_task(scope, task, get(attrs, :new_title), comment),
      else: {:ok, nil}
  end

  defp after_move(scope, task, updated, move, attrs) when move != nil do
    if Scope.agent?(scope) and updated.step != task.step do
      report!(scope, task.goal, task, %{
        "action" => "step",
        "from" => task.step,
        "to" => updated.step,
        "reasons" => List.wrap(attrs |> get(:reason) |> blank_to_nil())
      })
    end

    {:ok, nil}
  end

  defp after_move(_scope, _task, _updated, _move, _attrs), do: {:ok, nil}

  defp split_task(scope, task, title, comment) do
    with {:ok, new} <- create_task(scope, task.goal, %{"title" => title, "type" => "feature"}) do
      link = "/projects/#{task.project_id}/goals/#{task.goal.number}/tasks/#{task.number}"

      Repo.insert!(%Widget{
        project_id: task.project_id,
        goal_id: task.goal_id,
        task_id: new.id,
        section: "intent",
        position: 1,
        kind: "prose",
        data: %{"text" => "#{String.trim(comment)}\n\nSplit off from [#{ref(task)}](#{link})."},
        human: %{}
      })

      {:ok, new}
    end
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

      %{mover: :human} = t when scope.agent_session != nil ->
        {:error,
         "\"#{t.name}\" is the human's decision; no agent can make it. " <>
           "They press the button on the task page: #{task_url(task)}"}

      transition ->
        case unmet_conditions(task, transition) do
          [] -> {:ok, transition}
          reasons -> {:error, Enum.join(reasons, "; ")}
        end
    end
  end

  defp task_url(task) do
    task = Repo.preload(task, :goal)

    JarvisWeb.Endpoint.url() <>
      "/projects/#{task.project_id}/goals/#{task.goal.number}/tasks/#{task.number}"
  end

  @doc "Why the transition is not allowed yet, as human-readable reasons; `[]` when it is."
  def unmet_conditions(%Task{} = task, transition) do
    unmet_conditions(task, transition, task_widgets(task))
  end

  def unmet_conditions(task, transition, widgets) do
    conditions =
      Enum.flat_map(transition[:conditions] || [], &condition(&1, task, widgets))

    gates =
      for w <- widgets,
          w.kind == "quiz",
          w.data["mode"] == "gate",
          String.downcase(w.data["gates"] || "") == transition.name,
          open = Catalog.quiz_open_questions(w.data, w.human),
          open != [] do
        "quiz W#{w.id}: #{Enum.join(open, ", ")} not answered correctly"
      end

    conditions ++ gates
  end

  defp condition(:requirements_confirmed, _task, widgets) do
    case Enum.filter(widgets, &(&1.kind == "requirement")) do
      [] ->
        ["Write at least one requirement card first"]

      requirements ->
        case Enum.reject(requirements, & &1.human["confirmed"]) do
          [] -> []
          open -> ["#{Enum.map_join(open, ", ", & &1.data["id"])} not confirmed"]
        end
    end
  end

  defp condition(:review_current, _task, widgets), do: stale_reasons(widgets, ~w(review))

  defp condition(:evidence_current, _task, widgets),
    do: stale_reasons(widgets, ~w(review evidence))

  defp condition(:evidence, _task, widgets),
    do: evidence_problems(widgets) ++ stale_reasons(widgets, ~w(review evidence))

  defp condition(:quiz_answered, %Task{quiz_skipped: true}, _widgets), do: []

  defp condition(:quiz_answered, _task, widgets) do
    for w <- widgets,
        w.section == "quiz" and w.kind == "quiz",
        open = Catalog.quiz_unanswered(w.data, w.human),
        open != [] do
      "quiz W#{w.id}: #{Enum.join(open, ", ")} not answered (or the human skips the quiz)"
    end
  end

  defp stale_reasons(widgets, sections) do
    for w <- widgets, w.section in sections, stale = w.human["stale"] do
      "#{TaskType.section_label(:feature, w.section)} W#{w.id} is out of date (#{stale["because"]}); produce it again"
    end
  end

  # Evidence is the agent's report: Jarvis checks what it says, it runs nothing.
  defp evidence_problems(widgets) do
    evidence = widgets |> Enum.filter(&(&1.kind == "evidence")) |> List.last()
    reviewed? = Enum.any?(widgets, &(&1.section == "review" and &1.kind == "findings"))
    review = if reviewed?, do: [], else: ["the review report is missing"]

    case evidence do
      nil ->
        ["evidence is missing" | review]

      %{data: d} ->
        rows = Enum.group_by(d["requirements"] || [], & &1["requirement"])

        per_requirement =
          for %{kind: "requirement", data: %{"id" => id}} <- widgets,
              problem =
                (case rows[id] do
                   nil ->
                     "#{id} has no test"

                   list ->
                     if Enum.all?(list, &(&1["result"] == "passed")),
                       do: nil,
                       else: "#{id}'s test failed"
                 end),
              problem != nil,
              do: problem

        check = if d["result"] == "passed", do: [], else: ["the check failed"]
        check ++ per_requirement ++ review
    end
  end

  @doc """
  The human skips the quiz of a PR review in Quiz: `findings ready` no longer
  waits for answers, and the turn goes to the agent.
  """
  def skip_quiz(%Scope{} = scope, %Task{type: :pr_review, step: "quiz"} = task) do
    task = Repo.preload(task, :goal)

    Repo.transact(fn ->
      updated = task |> Ecto.Changeset.change(quiz_skipped: true, turn: :agent) |> Repo.update!()

      Repo.insert!(%Comment{
        goal_id: task.goal_id,
        task_id: task.id,
        author: :human,
        body: "",
        transition: "skip quiz",
        to_step: task.step,
        deliver: true
      })

      record!(scope, task.goal, task, "#{ref(task)}: skipped the quiz")
      {:ok, updated}
    end)
    |> notify(scope)
  end

  def skip_quiz(_scope, _task), do: {:error, :not_in_quiz}

  @doc """
  Saves the human's own view of a pull request (one concern per line) or skips
  it (`text` nil). Saving delivers the view to the listening session.
  """
  def save_picture(%Scope{} = scope, %Task{type: :pr_review} = task, text) do
    task = Repo.preload(task, :goal)

    picture =
      case text do
        nil ->
          Map.put(task.picture || %{}, "state", "skipped")

        text ->
          concerns =
            text
            |> String.split("\n")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))
            |> Enum.with_index(1)
            |> Enum.map(fn {t, i} -> %{"id" => "c#{i}", "text" => t} end)

          %{"state" => "saved", "text" => text, "concerns" => concerns}
      end

    if text != nil and picture["concerns"] == [] do
      {:error, :empty}
    else
      Repo.transact(fn ->
        updated = task |> Ecto.Changeset.change(picture: picture) |> Repo.update!()

        if text != nil do
          lines = Enum.map_join(picture["concerns"], "\n", &"- #{&1["id"]}: #{&1["text"]}")
          again = if (task.picture || %{})["state"] == "saved", do: " (changed)", else: ""

          Repo.insert!(%Comment{
            goal_id: task.goal_id,
            task_id: task.id,
            author: :human,
            body:
              "My view of the pull request#{again}, written before seeing your findings:\n\n#{lines}\n\n" <>
                "Compare it with your findings and record the matches as a view_matches widget in the picture section. Never change my concerns.",
            deliver: true
          })
        end

        record!(
          scope,
          task.goal,
          task,
          "#{ref(task)}: #{if text, do: "saved", else: "skipped"} your view"
        )

        {:ok, updated}
      end)
      |> notify(scope)
    end
  end

  @doc "True while the first-round findings of a PR review wait for the human's view."
  def picture_pending?(%Task{type: :pr_review, picture: picture}),
    do: (picture || %{})["state"] not in ~w(saved skipped not_asked)

  def picture_pending?(_task), do: false

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
  - `update`: `id`, `data` (replaces the data; clears an out-of-date mark)
  - `move`: `id`, `position`, optional `section`
  - `delete`: `id`
  - `judge`: `id` (a quiz), `question`, `correct`, `explanation`

  An agent writes a task's sections only while its step owns them. A changed
  requirement makes the task's evidence and review out of date; a round with
  a new head makes a PR review's quiz and findings out of date. `meta` takes
  the agent's `reason` and `needs` for its turn report.

  Returns `{:ok, ids}` with the widget id each op touched, or
  `{:error, {:widgets, messages}}` naming the failing op and its fields.
  """
  def apply_widget_ops(scope, goal, task, ops, meta \\ %{})

  def apply_widget_ops(%Scope{} = scope, %Goal{} = goal, task, ops, meta) when is_list(ops) do
    ctx = %{
      scope: scope,
      goal: goal,
      task: task,
      sections: sections_of(task),
      reason: meta |> get(:reason) |> blank_to_nil()
    }

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

          if needs = meta |> get(:needs) |> blank_to_nil(),
            do: put_needs!(scope, goal, task, needs)

          if task, do: Workspaces.focus(scope, task.id)
          {:ok, Enum.reverse(ids)}

        error ->
          error
      end
    end)
    |> notify(scope)
  end

  def apply_widget_ops(_scope, _goal, _task, _ops, _meta),
    do: {:error, {:widgets, ["ops: must be a list of operations"]}}

  defp blank_to_nil(value), do: if(blank?(value), do: nil, else: String.trim(to_string(value)))

  defp sections_of(nil), do: TaskType.sections(:goal)
  defp sections_of(%Task{type: type}), do: TaskType.sections(type)

  defp apply_op(ctx, %{"op" => "add"} = op) do
    with {:ok, section} <- resolve_section(ctx.sections, op["section"]),
         :ok <- check_owned(ctx, section),
         {:ok, kind} <- resolve_kind(op["kind"]),
         {:ok, data} <- Catalog.validate(kind, op["data"] || %{}),
         :ok <- check_against_task(ctx, kind, data) do
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
      change_report!(ctx, "added", nil, widget)
      cascade!(ctx, nil, widget)
      {:ok, widget.id}
    end
  end

  defp apply_op(ctx, %{"op" => "update"} = op) do
    with {:ok, widget} <- owned_widget(ctx, op["id"]),
         :ok <- check_owned(ctx, widget.section),
         {:ok, data} <- Catalog.validate(widget.kind, op["data"] || %{}),
         :ok <- check_against_task(ctx, widget.kind, data) do
      human =
        widget.kind
        |> Catalog.reconcile(widget.data, data, widget.human)
        |> Map.delete("stale")

      updated = widget |> Ecto.Changeset.change(data: data, human: human) |> Repo.update!()
      note_update!(ctx, widget)
      if data != widget.data, do: change_report!(ctx, "updated", widget, updated)
      if data != widget.data, do: cascade!(ctx, widget, updated)
      {:ok, widget.id}
    end
  end

  defp apply_op(ctx, %{"op" => "move"} = op) do
    with {:ok, widget} <- owned_widget(ctx, op["id"]),
         :ok <- check_owned(ctx, widget.section),
         {:ok, section} <- resolve_section(ctx.sections, op["section"] || widget.section),
         :ok <- check_owned(ctx, section) do
      old_section = widget.section
      moved = widget |> Ecto.Changeset.change(section: section) |> Repo.update!()
      if old_section != section, do: renumber!(ctx, old_section, nil)
      place!(ctx, moved, section, op["position"])
      note_update!(ctx, moved)
      if old_section != section, do: change_report!(ctx, "moved", widget, moved)
      {:ok, widget.id}
    end
  end

  defp apply_op(ctx, %{"op" => "delete"} = op) do
    with {:ok, widget} <- owned_widget(ctx, op["id"]),
         :ok <- check_owned(ctx, widget.section) do
      Repo.delete!(widget)
      renumber!(ctx, widget.section, nil)
      change_report!(ctx, "deleted", widget, nil)
      cascade!(ctx, widget, nil)
      {:ok, widget.id}
    end
  end

  defp apply_op(ctx, %{"op" => "judge"} = op) do
    with {:ok, widget} <- owned_widget(ctx, op["id"]),
         :ok <- check_owned(ctx, widget.section),
         {:ok, human} <-
           wrap_error(
             Catalog.judge(widget, to_string(op["question"]), op["correct"], op["explanation"])
           ) do
      widget = widget |> Ecto.Changeset.change(human: human) |> Repo.update!()

      if op["correct"] == false,
        do: stale_explained!(ctx.scope, widget, to_string(op["question"]))

      {:ok, widget.id}
    end
  end

  defp apply_op(_ctx, _op), do: {:error, "op must be add, update, move, delete, or judge"}

  # Each step owns the sections an agent may write in it; the human is never limited.
  defp check_owned(%{task: nil}, _section), do: :ok

  defp check_owned(%{scope: scope, task: task}, section) do
    if not Scope.agent?(scope) or section in TaskType.owned_sections(task.type, task.step) do
      :ok
    else
      owners =
        case TaskType.owning_steps(task.type, section) do
          [] -> "no step"
          steps -> Enum.map_join(steps, ", ", &TaskType.step_label(task.type, &1))
        end

      {:error,
       [
         "section #{section}: the step #{TaskType.step_label(task.type, task.step)} does not let an agent write it; steps that do: #{owners}"
       ]}
    end
  end

  # Evidence rows must name the task's own requirement cards.
  defp check_against_task(%{task: %Task{} = task}, "evidence", data) do
    known =
      for %{kind: "requirement", data: %{"id" => id}} <- task_widgets(task),
          into: MapSet.new(),
          do: id

    errors =
      for {row, i} <- Enum.with_index(data["requirements"] || [], 1),
          not MapSet.member?(known, row["requirement"]) do
        "requirements[#{i}].requirement: no requirement card #{row["requirement"]} on this task"
      end

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp check_against_task(_ctx, _kind, _data), do: :ok

  ## Out of date

  # What a change upstream makes out of date in the same task.
  defp cascade!(%{task: %Task{} = task} = ctx, before, after_) do
    widget = after_ || before

    cond do
      widget.kind == "requirement" ->
        id = (after_ || before).data["id"]
        targets = Enum.filter(task_widgets(task), &(&1.section in ~w(review evidence)))
        mark_stale!(ctx.scope, ctx.goal, task, targets, "#{id} changed", widget)

      widget.kind == "round" and after_ != nil and before == nil and
          after_.data["head"] != after_.data["previous_head"] ->
        targets =
          Enum.filter(
            task_widgets(task),
            &((&1.section == "quiz" and &1.kind == "quiz") or
                (&1.section == "findings" and &1.kind == "findings"))
          )

        mark_stale!(
          ctx.scope,
          ctx.goal,
          task,
          targets,
          "new head #{after_.data["head"]} in round #{after_.data["number"]}",
          widget
        )

      true ->
        :ok
    end
  end

  defp cascade!(_ctx, _before, _after), do: :ok

  defp mark_stale!(scope, goal, task, widgets, because, source) do
    for w <- widgets do
      stale = %{
        "because" => because,
        "source" => source && source.id,
        "section" => source && source.section
      }

      w |> Ecto.Changeset.change(human: Map.put(w.human, "stale", stale)) |> Repo.update!()

      report!(scope, goal, task, %{
        "action" => "stale",
        "widget" => w.id,
        "kind" => w.kind,
        "section" => w.section,
        "because" => because
      })
    end

    :ok
  end

  # A wrong answer to a Learn check question makes the explanation it tests out of date.
  defp stale_explained!(scope, %Widget{kind: "quiz", task_id: task_id} = quiz, qid)
       when not is_nil(task_id) do
    task = Repo.get!(Task, task_id) |> Repo.preload(:goal)
    question = Enum.find(quiz.data["questions"], &(&1["id"] == qid))

    with :learn <- task.type,
         %{"explains" => ref} when is_binary(ref) <- question,
         id when is_integer(id) <- to_int(ref),
         %Widget{} = target <-
           Repo.one(from w in owner_widgets(task.goal_id, task), where: w.id == ^id) do
      mark_stale!(scope, task.goal, task, [target], "wrong answer to #{qid}", quiz)
    else
      _ -> :ok
    end
  end

  defp stale_explained!(_scope, _widget, _qid), do: :ok

  ## Turn reports

  @doc """
  The turn reports of a goal (task `nil`) or task whose turn has ended:
  `{unread, read}`, each newest first.
  """
  def list_reports(%Goal{} = goal, task) do
    query =
      from r in Report,
        where: r.goal_id == ^goal.id and not is_nil(r.closed_at),
        order_by: [desc: r.id],
        preload: [:agent_session]

    query =
      case task do
        nil -> from r in query, where: is_nil(r.task_id)
        %Task{id: id} -> from r in query, where: r.task_id == ^id
      end

    query |> Repo.all() |> Enum.split_with(&is_nil(&1.read_at))
  end

  @doc "The human has read the turn report: it moves to the history."
  def read_report(%Scope{project: project} = scope, id) do
    case Repo.one(from r in Report, where: r.id == ^to_int(id) and r.project_id == ^project.id) do
      nil ->
        {:error, :not_found}

      report ->
        report
        |> Ecto.Changeset.change(read_at: DateTime.utc_now())
        |> Repo.update()
        |> notify(scope)
    end
  end

  defp change_report!(ctx, action, before, after_) do
    widget = after_ || before

    report!(ctx.scope, ctx.goal, ctx.task, %{
      "action" => action,
      "widget" => widget.id,
      "kind" => widget.kind,
      "section" => widget.section,
      "from_section" => before && before.section,
      "before" => before && before.data,
      "after" => after_ && after_.data,
      "reasons" => List.wrap(ctx.reason)
    })
  end

  defp put_needs!(scope, goal, task, needs) do
    case scope.agent_session do
      nil -> :ok
      _ -> report!(scope, goal, task, nil, needs)
    end
  end

  # Adds the entry to the session's report for this turn and owner, merging
  # repeated changes of one widget into one entry.
  defp report!(scope, goal, task, entry, needs \\ nil)
  defp report!(%Scope{agent_session: nil}, _goal, _task, _entry, _needs), do: :ok

  defp report!(
         %Scope{agent_session: %{id: session_id}, project: project},
         goal,
         task,
         entry,
         needs
       ) do
    session = Repo.get!(AgentSession, session_id)
    task_id = task && task.id
    goal_id = (goal && goal.id) || (task && task.goal_id)

    report =
      Repo.one(
        from r in Report,
          where:
            r.agent_session_id == ^session.id and r.turn == ^session.turn and
              r.goal_id == ^goal_id and is_nil(r.read_at),
          where:
            ^if(task_id,
              do: dynamic([r], r.task_id == ^task_id),
              else: dynamic([r], is_nil(r.task_id))
            ),
          order_by: [desc: r.id],
          limit: 1
      ) ||
        Repo.insert!(%Report{
          project_id: project.id,
          goal_id: goal_id,
          task_id: task_id,
          agent_session_id: session.id,
          turn: session.turn,
          entries: %{"items" => []}
        })

    items = if entry, do: merge_entry(Report.items(report), entry), else: Report.items(report)

    working? =
      Repo.one(from s in AgentSession, where: s.id == ^session.id, select: s.state) == :working

    report
    |> Ecto.Changeset.change(
      entries: %{"items" => items},
      needs: needs || report.needs,
      closed_at: if(working?, do: nil, else: report.closed_at || DateTime.utc_now())
    )
    |> Repo.update!()

    :ok
  end

  defp merge_entry(items, %{"widget" => id, "action" => action} = entry)
       when action in ~w(added updated moved deleted) do
    case Enum.find_index(items, &(&1["widget"] == id and &1["action"] in ~w(added updated moved))) do
      nil ->
        items ++ [entry]

      i ->
        old = Enum.at(items, i)

        merged =
          case {old["action"], action} do
            {"added", "deleted"} -> nil
            {"added", _} -> %{entry | "action" => "added", "before" => nil}
            {_, _} -> %{entry | "before" => old["before"], "from_section" => old["from_section"]}
          end

        merged =
          merged && Map.put(merged, "reasons", Enum.uniq(old["reasons"] ++ entry["reasons"]))

        if merged, do: List.replace_at(items, i, merged), else: List.delete_at(items, i)
    end
  end

  defp merge_entry(items, %{"widget" => id, "action" => "stale"} = entry) do
    if Enum.any?(items, &(&1["widget"] == id and &1["action"] == "stale")),
      do: items,
      else: items ++ [entry]
  end

  defp merge_entry(items, entry), do: items ++ [entry]

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

        if action == "answer" do
          answer = get_in(widget.human, ["answers", params["question"]])

          if answer && answer["correct"] == false,
            do: stale_explained!(scope, widget, params["question"])

          quiz_answered!(widget)
        end

        {:ok, widget}
      end)
      |> notify(scope)
    end
  end

  # Answering every question of a PR review's quiz gives the turn to the agent.
  defp quiz_answered!(%Widget{section: "quiz", task_id: task_id}) when not is_nil(task_id) do
    task = Repo.get!(Task, task_id)

    if task.type == :pr_review and task.step == "quiz" and turn(task) == :human do
      quizzes = Enum.filter(task_widgets(task), &(&1.section == "quiz" and &1.kind == "quiz"))

      if quizzes != [] and Enum.all?(quizzes, &(Catalog.quiz_unanswered(&1.data, &1.human) == [])) do
        task |> Ecto.Changeset.change(turn: :agent) |> Repo.update!()
      end
    end

    :ok
  end

  defp quiz_answered!(_widget), do: :ok

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

         %Comment{deliver: true} ->
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
  defp describe(%Ecto.Changeset{changes: changes, data: data}, move) do
    step =
      case {changes[:step], move} do
        {nil, {:transition, t}} ->
          t.name

        {nil, _} ->
          nil

        {to, _} ->
          "moved #{TaskType.step_label(data.type, data.step)} → #{TaskType.step_label(data.type, to)}"
      end

    claim =
      case Map.fetch(changes, :worktree_id) do
        {:ok, nil} -> "released"
        {:ok, _} -> "claimed"
        :error -> nil
      end

    handoff = changes[:turn] == :human && move == nil && "handed over to you"
    title = changes[:title] && "renamed"

    case Enum.reject([step, claim, handoff, title], &(&1 in [nil, false])) do
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

  # SQLite has no row locks. A write takes the database write lock, which makes
  # the number allocation after it safe; a read first could not upgrade to it.
  defp lock!(schema, id) do
    {1, _} = Repo.update_all(from(r in schema, where: r.id == ^id), set: [id: id])
    :ok
  end

  defp next_number(query), do: (Repo.one(from r in query, select: max(r.number)) || 0) + 1

  defp notify({:ok, _} = result, scope) do
    Workspaces.broadcast_change(scope.project.id)
    result
  end

  defp notify(error, _scope), do: error
end
