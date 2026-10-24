defmodule Jarvis.Planning.Task do
  @moduledoc """
  A task: one pull request's worth of a goal.

  Status follows the workflow: `todo` (requirements written), `ready` (sketch
  written, awaiting implementation), `done` (implemented and reviewed). The
  worktree is the checkout that has claimed the task. Numbered per goal; the
  number never changes or gets reused.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses [:todo, :ready, :done]

  @sections [
    intent: "Intent",
    requirements: "Requirements",
    examples: "Examples",
    constraints: "Constraints",
    assumptions: "Assumptions",
    out_of_scope: "Out of scope",
    open_questions: "Open questions",
    sketch: "Sketch",
    tests: "Tests"
  ]

  schema "tasks" do
    field :number, :integer
    field :title, :string
    field :status, Ecto.Enum, values: @statuses, default: :todo

    for {section, _label} <- @sections, do: field(section, :string)

    belongs_to :goal, Jarvis.Planning.Goal
    belongs_to :project, Jarvis.Workspaces.Project
    belongs_to :worktree, Jarvis.Workspaces.Worktree
    has_many :comments, Jarvis.Planning.Comment, preload_order: [asc: :id]
    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  @doc "The markdown sections of a task, in display order, as `{field, label}`."
  def sections, do: @sections

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :status | Keyword.keys(@sections)], empty_values: [])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :status])
    |> validate_length(:title, max: 200)
  end

  @doc "True when the open questions section holds anything other than \"None\"."
  def open_questions?(%__MODULE__{open_questions: text}) do
    case text && String.trim(text) do
      nil -> false
      "" -> false
      none -> not String.match?(none, ~r/^none\.?$/i)
    end
  end
end
