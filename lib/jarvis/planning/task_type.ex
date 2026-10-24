defmodule Jarvis.Planning.TaskType do
  @moduledoc """
  The built-in task types. A type fixes a task's lifecycle (steps and the
  transitions between them) and the sections of its page.

  A transition has a mover: `:agent` (with the pi command that works the step)
  or `:human` (a button on the task page). A transition's `condition` names a
  rule `Jarvis.Planning` checks before it allows the move; gate quizzes add
  their own condition to the transition they name.
  """

  @type key :: :feature | :research | :pr_review | :learn

  @goal_sections [
    {"intent", "Intent", ~w(prose callout)},
    {"scope", "Scope", ~w(prose callout)},
    {"glossary", "Glossary", ~w(glossary_term)},
    {"decisions", "Decisions", ~w(decision)}
  ]

  @types [
    feature: %{
      label: "Feature",
      icon: "hero-sparkles",
      sections: [
        {"intent", "Intent", ~w(prose callout)},
        {"requirements", "Requirements", ~w(requirement)},
        {"examples", "Examples", ~w(examples)},
        {"constraints", "Constraints", ~w(prose decision callout)},
        {"assumptions", "Assumptions", ~w(prose callout)},
        {"out_of_scope", "Out of scope", ~w(prose)},
        {"open_questions", "Open questions", ~w(prose callout)},
        {"sketch", "Sketch", ~w(prose diagram architecture walkthrough)},
        {"tests", "Tests", ~w(prose)}
      ],
      steps: [
        {"requirements", "Requirements",
         "/specify writes requirement cards; you confirm each one"},
        {"design", "Design", "/design sketches the change; /design-review approves it"},
        {"implementation", "Implementation", "/impl builds it"},
        {"review", "Review", "/impl-review reviews it"},
        {"done", "Done", "Implemented and reviewed"}
      ],
      transitions: [
        %{
          name: "approve requirements",
          from: "requirements",
          to: "design",
          mover: :human,
          condition: :requirements_confirmed
        },
        %{
          name: "approve design",
          from: "design",
          to: "implementation",
          mover: :agent,
          command: "/design-review"
        },
        %{
          name: "requirements question",
          from: "design",
          to: "requirements",
          mover: :agent,
          command: "/design"
        },
        %{
          name: "implemented",
          from: "implementation",
          to: "review",
          mover: :agent,
          command: "/impl"
        },
        %{name: "approve", from: "review", to: "done", mover: :agent, command: "/impl-review"},
        %{
          name: "request changes",
          from: "review",
          to: "implementation",
          mover: :agent,
          command: "/impl-review"
        }
      ]
    },
    research: %{
      label: "Research",
      icon: "hero-magnifying-glass",
      sections: [
        {"question", "Question", ~w(prose callout)},
        {"context", "Context", ~w(prose glossary_term diagram)},
        {"investigation", "Investigation", ~w(prose walkthrough diagram)},
        {"findings", "Findings", ~w(comparison diagram callout prose)},
        {"recommendation", "Recommendation", ~w(decision callout prose)},
        {"sources", "Sources", ~w(sources)}
      ],
      steps: [
        {"question", "Question", "You and the agent frame the question; you approve it"},
        {"investigation", "Investigation", "/research investigates"},
        {"findings", "Findings", "You weigh the findings"},
        {"done", "Done", "Recommendation accepted"}
      ],
      transitions: [
        %{name: "approve question", from: "question", to: "investigation", mover: :human},
        %{
          name: "findings ready",
          from: "investigation",
          to: "findings",
          mover: :agent,
          command: "/research"
        },
        %{name: "accept", from: "findings", to: "done", mover: :human},
        %{name: "dig deeper", from: "findings", to: "investigation", mover: :human}
      ]
    },
    pr_review: %{
      label: "PR review",
      icon: "hero-code-bracket-square",
      sections: [
        {"pull_request", "Pull request", ~w(prose callout)},
        {"walkthrough", "Walkthrough", ~w(walkthrough diagram architecture)},
        {"findings", "Findings", ~w(findings)},
        {"verdict", "Verdict", ~w(decision callout)}
      ],
      steps: [
        {"intake", "Intake", "Name the pull request; /pr-review takes it up"},
        {"walkthrough", "Walkthrough", "/pr-review walks through the change"},
        {"findings", "Findings", "You answer each finding and give the verdict"},
        {"done", "Done", "Verdict given"}
      ],
      transitions: [
        %{
          name: "start walkthrough",
          from: "intake",
          to: "walkthrough",
          mover: :agent,
          command: "/pr-review"
        },
        %{
          name: "findings ready",
          from: "walkthrough",
          to: "findings",
          mover: :agent,
          command: "/pr-review"
        },
        %{name: "give verdict", from: "findings", to: "done", mover: :human},
        %{name: "look again", from: "findings", to: "walkthrough", mover: :human}
      ]
    },
    learn: %{
      label: "Learn",
      icon: "hero-academic-cap",
      sections: [
        {"topic", "Topic", ~w(prose glossary_term)},
        {"explanation", "Explanation", ~w(walkthrough architecture diagram glossary_term prose)},
        {"check", "Check", ~w(quiz)}
      ],
      steps: [
        {"topic", "Topic", "Name what you want to understand; /learn takes it up"},
        {"explanation", "Explanation", "/learn explains it"},
        {"check", "Check", "You take the quiz"},
        {"done", "Done", "Understood"}
      ],
      transitions: [
        %{name: "explain", from: "topic", to: "explanation", mover: :agent, command: "/learn"},
        %{
          name: "check understanding",
          from: "explanation",
          to: "check",
          mover: :agent,
          command: "/learn"
        },
        %{name: "passed", from: "check", to: "done", mover: :human},
        %{name: "gaps found", from: "check", to: "explanation", mover: :human}
      ]
    }
  ]

  @keys Keyword.keys(@types)

  def keys, do: @keys
  def all, do: @types

  @doc "Parses a type name from the API or the UI; `nil` for an unknown name."
  def parse(value) when is_atom(value) and value in @keys, do: value

  def parse(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase() |> String.replace([" ", "-"], "_")
    Enum.find(@keys, &(Atom.to_string(&1) == normalized))
  end

  def parse(_), do: nil

  def label(type), do: fetch!(type).label
  def icon(type), do: fetch!(type).icon

  @doc "Sections as `{key, label, recommended widget kinds}`."
  def sections(:goal), do: @goal_sections
  def sections(type), do: fetch!(type).sections

  def steps(type), do: fetch!(type).steps
  def first_step(type), do: type |> steps() |> hd() |> elem(0)

  def step_label(type, step) do
    case List.keyfind(steps(type), step, 0) do
      {_, label, _} -> label
      nil -> step
    end
  end

  def step?(type, step), do: List.keymember?(steps(type), step, 0)

  def transitions(type), do: fetch!(type).transitions

  def transitions_from(type, step), do: Enum.filter(transitions(type), &(&1.from == step))

  @doc "Finds a transition out of `step` by name, ignoring case."
  def find_transition(type, step, name) when is_binary(name) do
    wanted = name |> String.trim() |> String.downcase()
    Enum.find(transitions_from(type, step), &(&1.name == wanted))
  end

  def done?(step), do: step == "done"

  defp fetch!(type), do: Keyword.fetch!(@types, type)
end
