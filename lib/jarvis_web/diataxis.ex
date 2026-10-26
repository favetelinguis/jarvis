defmodule JarvisWeb.Diataxis do
  @moduledoc """
  The four Diátaxis forms and which one each page and each section of the
  board has. A page or section has exactly one form; the form decides how it
  is written (see `.agents/skills/jarvis-design`), never its visual style.
  """

  @type form :: :tutorial | :how_to | :reference | :explanation

  @forms [
    tutorial: {"Tutorial", "Learn by doing: follow the steps and check the result."},
    how_to: {"How-to", "Get one job done: follow numbered steps."},
    reference: {"Reference", "Look up facts: every entry has the same fields."},
    explanation: {"Explanation", "Understand why: read the reasons and the context."}
  ]

  # Every section key of every task type (and the goal) has one form.
  @sections %{
    goal: %{
      "intent" => :explanation,
      "scope" => :reference,
      "glossary" => :reference,
      "decisions" => :explanation
    },
    feature: %{
      "intent" => :explanation,
      "requirements" => :reference,
      "examples" => :reference,
      "constraints" => :reference,
      "assumptions" => :reference,
      "out_of_scope" => :reference,
      "open_questions" => :reference,
      "sketch" => :explanation,
      "tests" => :reference
    },
    research: %{
      "question" => :reference,
      "context" => :explanation,
      "investigation" => :explanation,
      "findings" => :explanation,
      "recommendation" => :explanation,
      "sources" => :reference
    },
    pr_review: %{
      "pull_request" => :reference,
      "background" => :explanation,
      "intuition" => :explanation,
      "code" => :explanation,
      "quiz" => :tutorial,
      "rounds" => :reference,
      "findings" => :reference,
      "comments" => :reference,
      "verdict" => :reference
    },
    learn: %{
      "topic" => :tutorial,
      "explanation" => :tutorial,
      "check" => :tutorial
    }
  }

  # A task page has the form of its type: a Learn task is a tutorial.
  @task_pages %{
    feature: :reference,
    research: :explanation,
    pr_review: :explanation,
    learn: :tutorial
  }

  @doc "The four forms in order, as `{form, label, purpose}`."
  def all, do: for({form, {label, purpose}} <- @forms, do: {form, label, purpose})

  def label(form), do: @forms |> Keyword.fetch!(form) |> elem(0)
  def purpose(form), do: @forms |> Keyword.fetch!(form) |> elem(1)

  @doc "The form of a section of a goal (`:goal`) or a task type."
  def section(type, key), do: @sections |> Map.fetch!(type) |> Map.fetch!(key)

  @doc "The form of a task page of a type."
  def task_page(type), do: Map.fetch!(@task_pages, type)
end
