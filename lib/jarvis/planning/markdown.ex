defmodule Jarvis.Planning.Markdown do
  @moduledoc """
  Renders goals and tasks as markdown for agents: sections in order, each
  widget with its widget id, kind, and part ids, so an agent can point at the
  same thing the human sees in the UI.
  """

  alias Jarvis.Planning
  alias Jarvis.Planning.{Catalog, Comment, Goal, Task, TaskType}
  alias Jarvis.Workspaces.{AgentSession, Worktree}

  @doc "Every goal with one line per task, then the project's live agent sessions."
  def overview(project, goals, sessions, now \\ DateTime.utc_now()) do
    goal_blocks =
      case goals do
        [] -> ["No goals yet."]
        goals -> Enum.map(goals, &goal_summary/1)
      end

    session_lines =
      sessions
      |> Enum.reject(&(AgentSession.presence(&1, now) == :ended))
      |> Enum.map(&session_line(&1, now))

    sessions_block =
      if session_lines == [], do: [], else: ["## Agent sessions", Enum.join(session_lines, "\n")]

    join([Jarvis.Language.line(), "# Project #{project.name}" | goal_blocks] ++ sessions_block)
  end

  defp goal_summary(%Goal{tasks: tasks} = goal) do
    done = Enum.count(tasks, &Task.done?/1)
    lines = Enum.map(tasks, &task_line(%{&1 | goal: goal}))

    Enum.join(
      [
        "## #{Planning.ref(goal)}: #{goal.title}#{poc_tag(goal)} (#{done} of #{length(tasks)} done)"
        | lines
      ],
      "\n"
    )
  end

  defp poc_tag(%Goal{poc: true}), do: " [POC, unreviewed]"
  defp poc_tag(_), do: ""

  defp task_line(%Task{} = task) do
    worktree = task.worktree && "worktree #{Worktree.label(task.worktree)}"
    suffix = if worktree, do: " — " <> worktree, else: ""

    "- #{Planning.ref(task)}: #{task.title} [#{TaskType.label(task.type)} · #{TaskType.step_label(task.type, task.step)}]#{suffix}"
  end

  defp session_line(%AgentSession{} = session, now) do
    focus = if session.task, do: ", focus #{Planning.ref(session.task)}", else: ""
    name = session.name || String.slice(session.pi_session_id, 0, 8)

    "- #{name} in #{Worktree.label(session.worktree)}: #{AgentSession.presence(session, now)}#{focus}"
  end

  @doc "The whole goal: its sections as widgets, its tasks one line each, and its comments."
  def goal(%Goal{} = goal, widgets) do
    tasks = Enum.map(goal.tasks, &task_line(%{&1 | goal: goal}))
    tasks = ["## Tasks\n\n" <> if(tasks == [], do: "No tasks yet.", else: Enum.join(tasks, "\n"))]

    join(
      [Jarvis.Language.line(), "# #{Planning.ref(goal)}: #{goal.title}#{poc_tag(goal)}"] ++
        sections(TaskType.sections(:goal), widgets) ++ tasks ++ comments(goal.comments)
    )
  end

  @doc """
  The whole task: type, step, the transitions out of it, its worktree line, its
  sections as widgets, and its comments.
  """
  def task(%Task{goal: %Goal{} = goal} = task, widgets) do
    header =
      "# #{Planning.ref(task)}: #{task.title}\n\nPart of #{Planning.ref(goal)}: #{goal.title}"

    worktree =
      "**Worktree:** " <> if(task.worktree, do: Worktree.label(task.worktree), else: "unclaimed")

    join(
      [Jarvis.Language.line(), header, worktree, lifecycle(task, widgets)] ++
        sections(TaskType.sections(task.type), widgets) ++ comments(task.comments)
    )
  end

  defp lifecycle(%Task{type: type, step: step} = task, widgets) do
    previous =
      if task.previous_step,
        do: "; came from #{TaskType.step_label(type, task.previous_step)}",
        else: ""

    transitions =
      case TaskType.transitions_from(type, step) do
        [] ->
          ["No transitions: this step ends the lifecycle."]

        transitions ->
          for t <- transitions do
            mover =
              if t.mover == :human,
                do: "the human only (a button on the task page; never make it yourself)",
                else: "an agent (#{t.command})"

            unmet = Planning.unmet_conditions(task, t, widgets)
            blocked = if unmet == [], do: "", else: " — blocked: #{Enum.join(unmet, "; ")}"
            comment = if t[:comment], do: ", with the human's comment", else: ""

            "- \"#{t.name}\" → #{TaskType.step_label(type, t.to)}, moved by #{mover}#{comment}#{blocked}"
          end
      end

    turn =
      case Planning.turn(task) do
        :human ->
          "**Turn:** the human's. Wait for their decision; work only on what their comments ask."

        {:agent, command} ->
          handoff =
            if step in TaskType.handoff_steps(type),
              do:
                " When your work in this step is ready for the human, hand it over with jarvis_task_save `handoff: true`.",
              else: ""

          "**Turn:** the agent's#{if command, do: " (#{command})"}.#{handoff}"

        :none ->
          "**Turn:** nobody's."
      end

    owned =
      case TaskType.owned_sections(type, step) do
        [] -> "**Sections you may write in this step:** none."
        keys -> "**Sections you may write in this step:** #{Enum.join(keys, ", ")}."
      end

    Enum.join(
      [
        "**Type:** #{TaskType.label(type)}  \n**Step:** #{TaskType.step_label(type, step)}#{previous}",
        turn,
        owned,
        "**Transitions out of this step** (move with jarvis_task_save transition):"
        | transitions
      ],
      "\n"
    )
  end

  defp sections(sections, widgets) do
    by_section = Enum.group_by(widgets, & &1.section)

    for {key, label, recommended} <- sections do
      body =
        case Map.get(by_section, key, []) do
          [] -> "_Nothing yet._ Recommended widgets: #{Enum.join(recommended, ", ")}."
          widgets -> Enum.map_join(widgets, "\n\n", &Catalog.text/1)
        end

      "## #{label} (`#{key}`)\n\n#{body}"
    end
  end

  @doc "Comments delivered to an agent at the start of its turn."
  def inbox(comments) do
    items =
      Enum.map(comments, fn %Comment{} = c ->
        target = if c.task, do: Planning.ref(%{c.task | goal: c.goal}), else: Planning.ref(c.goal)
        "### On #{target}\n\n#{c.body}"
      end)

    join(["# New comments from the human in Jarvis" | items])
  end

  @doc """
  Anchored comments that woke a session: what was pointed at, the content as it
  is now, and how to answer.
  """
  def wake(comments) do
    {plain, anchored} = Enum.split_with(comments, &is_nil(&1.anchor_label))

    moves =
      Enum.map(plain, fn %Comment{} = c ->
        target = if c.task, do: Planning.ref(%{c.task | goal: c.goal}), else: Planning.ref(c.goal)

        case c.transition do
          nil ->
            "### The human on #{target}\n\n#{c.body}"

          "skip quiz" ->
            "### The human skipped the quiz of #{target}\n\nWrite the findings now; `findings ready` no longer waits for answers."

          name ->
            step =
              if c.task, do: TaskType.step_label(c.task.type, c.to_step), else: c.to_step

            comment = if c.body == "", do: "", else: "\n\nTheir comment:\n\n#{c.body}"
            "### The human moved #{target}: \"#{name}\" → #{step}#{comment}"
        end
      end)

    if anchored == [] do
      join(["# Moves and messages from the human in Jarvis" | moves])
    else
      anchored_text = wake_anchored(anchored)

      if moves == [],
        do: anchored_text,
        else:
          join(["# Moves and messages from the human in Jarvis" | moves]) <> "\n" <> anchored_text
    end
  end

  defp wake_anchored(comments) do
    items =
      Enum.map(comments, fn %Comment{} = c ->
        target = if c.task, do: Planning.ref(%{c.task | goal: c.goal}), else: Planning.ref(c.goal)
        part = if c.part, do: ", part `#{c.part}`", else: ""
        who = if c.author == :human, do: "The human commented", else: "Jarvis reports"

        """
        ### #{who} on #{target} — #{c.anchor_label}

        Comment #{c.id}, widget W#{c.widget_id}#{part}.

        Anchor content:

        > #{String.replace(c.anchor_text || "", "\n", "\n> ")}

        #{c.body}\
        """
      end)

    footer =
      "Change the widget with jarvis_widgets (op update), or answer in its thread with jarvis_comment (reply_to: the comment id). " <>
        "If the comment is only a question, answer it; do not change the widget."

    join(["# Comments on widgets in Jarvis" | items] ++ [footer])
  end

  defp comments([]), do: []

  defp comments(comments) do
    plain = Enum.reject(comments, &Comment.anchored?/1)
    anchored = Enum.filter(comments, &(Comment.anchored?(&1) and &1.author != :system))

    items =
      Enum.map(plain, fn %Comment{} = c ->
        "- **#{c.author}** (#{stamp(c)}): " <> String.replace(c.body, "\n", "\n  ")
      end)

    threads =
      Enum.map(anchored, fn %Comment{} = c ->
        "- #{c.id} on #{c.anchor_label}, **#{c.author}** (#{stamp(c)}): " <>
          String.replace(c.body, "\n", "\n  ")
      end)

    List.flatten([
      if(items == [], do: [], else: ["## Comments\n\n" <> Enum.join(items, "\n")]),
      if(threads == [], do: [], else: ["## Comments on widgets\n\n" <> Enum.join(threads, "\n")])
    ])
  end

  defp stamp(c), do: Calendar.strftime(c.inserted_at, "%Y-%m-%d %H:%M") <> " UTC"

  @doc "The widget catalog for agents: every kind with its fields, parts, and an example."
  def catalog do
    kinds =
      for kind <- Catalog.kinds() do
        fields = Enum.map_join(Catalog.fields(kind), "\n", &field_line(&1, ""))

        """
        ### #{kind} — #{Catalog.label(kind)}

        #{Catalog.description(kind)}

        Fields (* = required):
        #{fields}

        Example data:
        ```json
        #{Jason.encode!(Catalog.example(kind), pretty: true)}
        ```\
        """
      end

    sections =
      for type <- TaskType.keys() do
        rows =
          Enum.map_join(TaskType.sections(type), "\n", fn {key, label, kinds} ->
            "- `#{key}` (#{label}): #{Enum.join(kinds, ", ")}"
          end)

        "### #{TaskType.label(type)} task sections and recommended widgets\n\n#{rows}"
      end

    goal_rows =
      Enum.map_join(TaskType.sections(:goal), "\n", fn {key, label, kinds} ->
        "- `#{key}` (#{label}): #{Enum.join(kinds, ", ")}"
      end)

    join(
      [
        "# Jarvis widget catalog",
        "Write widgets with jarvis_widgets. List items take an optional `id`; keep an item's id when you change it so comments and the human's answers stay attached.",
        "## Widget kinds"
      ] ++
        kinds ++
        ["## Sections", "### Goal sections\n\n#{goal_rows}"] ++ sections
    )
  end

  defp field_line({name, type, opts}, indent) do
    required = if opts[:required], do: "*", else: ""
    doc = if opts[:doc], do: " — #{opts[:doc]}", else: ""

    "#{indent}- `#{name}`#{required}: #{type_text(type)}#{doc}" <> nested(type, indent)
  end

  defp nested({:list, _, fields}, indent), do: nested({:list, nil, fields, []}, indent)

  defp nested({:list, _, fields, _}, indent),
    do: "\n" <> Enum.map_join(fields, "\n", &field_line(&1, indent <> "  "))

  defp nested(_, _), do: ""

  defp type_text(:string), do: "string"
  defp type_text(:text), do: "text (markdown)"
  defp type_text(:bool), do: "boolean"
  defp type_text({:enum, values}), do: "one of " <> Enum.join(values, " | ")
  defp type_text({:int, min, max}), do: "integer #{min}-#{max}"
  defp type_text({:strings, _}), do: "list of strings"
  defp type_text({:map, t}), do: "object of #{type_text(t)}"

  defp type_text({:list, prefix, _}),
    do: "list of objects (ids default to #{prefix}1, #{prefix}2, …)"

  defp type_text({:list, prefix, _, _}), do: "list of objects (each needs an `id`; #{prefix})"

  defp join(blocks), do: Enum.join(blocks, "\n\n") <> "\n"
end
