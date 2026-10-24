defmodule Jarvis.Planning.Markdown do
  @moduledoc """
  Renders goals and tasks as markdown for agents, in the shape of the workflow's
  goal files, so an agent reads the same document a human sees in the UI.
  """

  alias Jarvis.Planning
  alias Jarvis.Planning.{Comment, Goal, Task}
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

    join(["# Project #{project.name}" | goal_blocks] ++ sessions_block)
  end

  defp goal_summary(%Goal{tasks: tasks} = goal) do
    counts = Enum.frequencies_by(tasks, & &1.status)
    tally = Enum.map_join(Task.statuses(), ", ", &"#{Map.get(counts, &1, 0)} #{&1}")
    lines = Enum.map(tasks, &task_line(%{&1 | goal: goal}))
    Enum.join(["## #{Planning.ref(goal)}: #{goal.title} (#{tally})" | lines], "\n")
  end

  defp task_line(%Task{} = task) do
    extras =
      [
        task.worktree && "worktree #{Worktree.label(task.worktree)}",
        Task.open_questions?(task) && "has open questions"
      ]
      |> Enum.filter(&is_binary/1)

    suffix = if extras == [], do: "", else: " — " <> Enum.join(extras, "; ")
    "- #{Planning.ref(task)}: #{task.title} [#{task.status}]#{suffix}"
  end

  defp session_line(%AgentSession{} = session, now) do
    focus = if session.task, do: ", focus #{Planning.ref(session.task)}", else: ""
    name = session.name || String.slice(session.pi_session_id, 0, 8)

    "- #{name} in #{Worktree.label(session.worktree)}: #{AgentSession.presence(session, now)}#{focus}"
  end

  @doc "The whole goal: its sections, its tasks one line each, and its goal-level comments."
  def goal(%Goal{} = goal) do
    sections =
      for {field, label} <- Goal.sections() do
        "## #{label}\n\n#{blank_to(Map.fetch!(goal, field), "_Not written yet._")}"
      end

    tasks = Enum.map(goal.tasks, &task_line(%{&1 | goal: goal}))
    tasks = ["## Tasks\n\n" <> if(tasks == [], do: "No tasks yet.", else: Enum.join(tasks, "\n"))]

    join(
      ["# #{Planning.ref(goal)}: #{goal.title}"] ++ sections ++ tasks ++ comments(goal.comments)
    )
  end

  @doc "The whole task, with its worktree line, every written section, and its comments."
  def task(%Task{goal: %Goal{} = goal} = task) do
    header =
      "# #{Planning.ref(task)}: #{task.title} [#{task.status}]\n\nPart of #{Planning.ref(goal)}: #{goal.title}"

    worktree =
      "**Worktree:** " <> if(task.worktree, do: Worktree.label(task.worktree), else: "unclaimed")

    sections =
      for {field, label} <- Task.sections(),
          text = Map.fetch!(task, field),
          text not in [nil, ""] do
        if String.contains?(text, "\n") or String.match?(text, ~r/^\s*[-|*]/),
          do: "**#{label}:**\n\n#{text}",
          else: "**#{label}:** #{text}"
      end

    join([header, worktree | sections] ++ comments(task.comments))
  end

  @doc "Human comments delivered to an agent at the start of its turn."
  def inbox(comments) do
    items =
      Enum.map(comments, fn %Comment{} = c ->
        target = if c.task, do: Planning.ref(%{c.task | goal: c.goal}), else: Planning.ref(c.goal)
        "### On #{target}\n\n#{c.body}"
      end)

    join(["# New comments from the human in Jarvis" | items])
  end

  defp comments([]), do: []

  defp comments(comments) do
    items =
      Enum.map(comments, fn %Comment{} = c ->
        "- **#{c.author}** (#{Calendar.strftime(c.inserted_at, "%Y-%m-%d %H:%M")} UTC): " <>
          String.replace(c.body, "\n", "\n  ")
      end)

    ["## Comments\n\n" <> Enum.join(items, "\n")]
  end

  defp blank_to(text, default) when text in [nil, ""], do: default
  defp blank_to(text, _default), do: text

  defp join(blocks), do: Enum.join(blocks, "\n\n") <> "\n"
end
