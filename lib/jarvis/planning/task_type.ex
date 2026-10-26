defmodule Jarvis.Planning.TaskType do
  @moduledoc """
  The built-in task types. A type fixes a task's lifecycle (steps and the
  transitions between them), the sections of its page, who has the turn when
  each step begins, and which sections each step lets an agent write.

  A transition has a mover: `:agent` (with the command that works the step)
  or `:human` (a button on the task page; no agent can make it). `conditions`
  name rules `Jarvis.Planning` checks before it allows the move; gate quizzes
  add their own condition to the transition they name. `comment: true` means
  the human must say what to change; `creates_task: true` splits the comment
  off into a new Feature task.

  A step's turn is `{:agent, command, handoff?}`, `:human`, or `:none`. An
  agent hands a handoff step over to the human without leaving it.
  """

  @type key :: :feature | :research | :pr_review | :learn

  @goal_sections [
    {"intent", "Intent", ~w(prose callout)},
    {"scope", "Scope", ~w(prose callout)},
    {"glossary", "Glossary", ~w(glossary_term)},
    {"decisions", "Decisions", ~w(decision)}
  ]

  @spec_sections ~w(intent requirements examples constraints assumptions out_of_scope open_questions)

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
        {"tests", "Tests", ~w(prose)},
        {"review", "Review", ~w(findings)},
        {"evidence", "Evidence", ~w(evidence)}
      ],
      steps: [
        {"requirements", "Requirements",
         "/specify writes requirement cards; you confirm each one and approve them"},
        {"design", "Design",
         "/design sketches the change and has it reviewed in a fresh context; you approve it"},
        {"implementation", "Implementation",
         "/impl builds it, has it reviewed, and records the evidence"},
        {"acceptance", "Acceptance", "You weigh the evidence and the review, and accept it"},
        {"done", "Done", "Implemented and accepted"}
      ],
      turns: %{
        "requirements" => {:agent, "/specify", true},
        "design" => {:agent, "/design", true},
        "implementation" => {:agent, "/impl", false},
        "acceptance" => :human,
        "done" => :none
      },
      owns: %{
        "requirements" => @spec_sections,
        "design" => @spec_sections ++ ~w(sketch tests review),
        "implementation" => ~w(sketch tests review evidence),
        "acceptance" => [],
        "done" => []
      },
      transitions: [
        %{
          name: "approve requirements",
          from: "requirements",
          to: "design",
          mover: :human,
          conditions: [:requirements_confirmed]
        },
        %{
          name: "requirements question",
          from: "design",
          to: "requirements",
          mover: :agent,
          command: "/design"
        },
        %{
          name: "approve design",
          from: "design",
          to: "implementation",
          mover: :human,
          conditions: [:requirements_confirmed, :review_current]
        },
        %{
          name: "request design changes",
          from: "design",
          to: "design",
          mover: :human,
          comment: true
        },
        %{
          name: "implemented",
          from: "implementation",
          to: "acceptance",
          mover: :agent,
          command: "/impl",
          conditions: [:requirements_confirmed, :evidence]
        },
        %{
          name: "accept",
          from: "acceptance",
          to: "done",
          mover: :human,
          conditions: [:requirements_confirmed, :evidence_current]
        },
        %{
          name: "request changes",
          from: "acceptance",
          to: "implementation",
          mover: :human,
          comment: true
        },
        %{
          name: "spec issue",
          from: "acceptance",
          to: "acceptance",
          mover: :human,
          comment: true,
          creates_task: true
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
        {"question", "Question", "/research frames the question with you; you approve it"},
        {"investigation", "Investigation", "/research investigates"},
        {"findings", "Findings", "You weigh the findings"},
        {"done", "Done", "Recommendation accepted"}
      ],
      turns: %{
        "question" => {:agent, "/research", true},
        "investigation" => {:agent, "/research", false},
        "findings" => :human,
        "done" => :none
      },
      owns: %{
        "question" => ~w(question context),
        "investigation" => ~w(context investigation findings recommendation sources),
        "findings" => [],
        "done" => []
      },
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
        %{
          name: "dig deeper",
          from: "findings",
          to: "investigation",
          mover: :human,
          comment: true
        }
      ]
    },
    pr_review: %{
      label: "PR review",
      icon: "hero-code-bracket-square",
      sections: [
        {"pull_request", "Pull request", ~w(prose callout discussion)},
        {"background", "Background", ~w(prose architecture diagram glossary_term callout)},
        {"intuition", "Intuition", ~w(prose diagram examples callout)},
        {"code", "Code", ~w(walkthrough diagram architecture)},
        {"quiz", "Quiz", ~w(quiz)},
        {"rounds", "Re-reviews", ~w(round discussion findings)},
        {"picture", "Your view", ~w(view_matches)},
        {"findings", "Findings", ~w(findings)},
        {"comments", "Comments for the author", ~w(draft_comments)},
        {"verdict", "Verdict", ~w(decision callout)}
      ],
      steps: [
        {"intake", "Intake", "Name the pull request; /pr-review takes it up"},
        {"explanation", "Explanation",
         "/pr-review explains the change: background, intuition, code, and a quiz"},
        {"quiz", "Quiz", "You check that you understood the change"},
        {"findings", "Findings",
         "You write your view, answer each finding, and give the verdict"},
        {"done", "Done", "Verdict given"}
      ],
      turns: %{
        "intake" => {:agent, "/pr-review", false},
        "explanation" => {:agent, "/pr-review", true},
        "quiz" => :human,
        "findings" => :human,
        "done" => :none
      },
      owns: %{
        "intake" => ~w(pull_request),
        "explanation" => ~w(pull_request background intuition code quiz),
        "quiz" => ~w(background intuition code quiz findings comments),
        "findings" => ~w(rounds picture findings comments verdict),
        "done" => ~w(comments)
      },
      transitions: [
        %{
          name: "start explanation",
          from: "intake",
          to: "explanation",
          mover: :agent,
          command: "/pr-review"
        },
        %{name: "ready for the quiz", from: "explanation", to: "quiz", mover: :human},
        %{
          name: "findings ready",
          from: "quiz",
          to: "findings",
          mover: :agent,
          command: "/pr-review",
          conditions: [:quiz_answered]
        },
        %{name: "give verdict", from: "findings", to: "done", mover: :human},
        %{
          name: "look again",
          from: "findings",
          to: "explanation",
          mover: :human,
          comment: true
        },
        %{name: "re-review", from: "done", to: "findings", mover: :human}
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
        {"explanation", "Explanation", "/learn explains it and writes the check"},
        {"check", "Check", "You take the quiz"},
        {"done", "Done", "Understood"}
      ],
      turns: %{
        "topic" => {:agent, "/learn", false},
        "explanation" => {:agent, "/learn", true},
        "check" => :human,
        "done" => :none
      },
      owns: %{
        "topic" => ~w(topic),
        "explanation" => ~w(topic explanation check),
        "check" => ~w(explanation check),
        "done" => []
      },
      transitions: [
        %{name: "explain", from: "topic", to: "explanation", mover: :agent, command: "/learn"},
        %{name: "check understanding", from: "explanation", to: "check", mover: :human},
        %{name: "passed", from: "check", to: "done", mover: :human},
        %{
          name: "gaps found",
          from: "check",
          to: "explanation",
          mover: :human,
          comment: true
        }
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

  def section_label(type, key) do
    case List.keyfind(sections(type), key, 0) do
      {_, label, _} -> label
      nil -> key
    end
  end

  def steps(type), do: fetch!(type).steps
  def first_step(type), do: type |> steps() |> hd() |> elem(0)

  def step_label(type, step) do
    case List.keyfind(steps(type), step, 0) do
      {_, label, _} -> label
      nil -> step
    end
  end

  @doc "What happens in a step, in one line (the third element of its definition)."
  def step_description(type, step) do
    case List.keyfind(steps(type), step, 0) do
      {_, _, description} -> description
      nil -> step
    end
  end

  def step?(type, step), do: List.keymember?(steps(type), step, 0)

  @doc "Who has the turn when the step begins: `{:agent, command, handoff?}`, `:human`, or `:none`."
  def start_turn(type, step), do: Map.get(fetch!(type).turns, step, :none)

  @doc "The steps an agent hands over to the human without leaving them."
  def handoff_steps(type) do
    for {key, _, _} <- steps(type), match?({:agent, _, true}, start_turn(type, key)), do: key
  end

  @doc "The section keys an agent may write while the task is in `step`."
  def owned_sections(type, step), do: Map.get(fetch!(type).owns, step, [])

  @doc "The steps in which an agent may write the section."
  def owning_steps(type, section) do
    for {key, _, _} <- steps(type), section in owned_sections(type, key), do: key
  end

  def transitions(type), do: fetch!(type).transitions

  def transitions_from(type, step), do: Enum.filter(transitions(type), &(&1.from == step))

  @doc "Finds a transition out of `step` by name, ignoring case."
  def find_transition(type, step, name) when is_binary(name) do
    wanted = name |> String.trim() |> String.downcase()
    Enum.find(transitions_from(type, step), &(&1.name == wanted))
  end

  @doc "The agent transitions a workflow command (such as `/impl`) makes."
  def transitions_of(command) do
    for {type, _} <- @types, t <- transitions(type), t[:command] == command, do: {type, t}
  end

  def done?(step), do: step == "done"

  defp fetch!(type), do: Keyword.fetch!(@types, type)
end
