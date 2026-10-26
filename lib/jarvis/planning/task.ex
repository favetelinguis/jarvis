defmodule Jarvis.Planning.Task do
  @moduledoc """
  A task: one reviewable piece of a goal. Its task type fixes its lifecycle and
  sections; `step` is where it is in that lifecycle and `previous_step` the step
  it last left. The worktree is the checkout that has claimed the task.
  Numbered per goal; the number never changes or gets reused.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Jarvis.Planning.TaskType

  @type t :: %__MODULE__{}

  schema "tasks" do
    field :number, :integer
    field :title, :string
    field :type, Ecto.Enum, values: TaskType.keys()
    field :step, :string
    field :previous_step, :string
    # nil: whoever the step gives the turn to when it begins (TaskType.start_turn/2)
    field :turn, Ecto.Enum, values: [:agent, :human]
    field :quiz_skipped, :boolean, default: false
    # PR review: the human's own concerns before seeing the agent's findings
    field :picture, :map, default: %{}

    belongs_to :goal, Jarvis.Planning.Goal
    belongs_to :project, Jarvis.Workspaces.Project
    belongs_to :worktree, Jarvis.Workspaces.Worktree
    has_many :comments, Jarvis.Planning.Comment, preload_order: [asc: :id]
    timestamps(type: :utc_datetime_usec)
  end

  @doc "A new task: title from `attrs`; the type and first step are set by the caller."
  def create_changeset(task, attrs), do: title_changeset(task, attrs)

  def title_changeset(task, attrs) do
    task
    |> cast(attrs, [:title], empty_values: [])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
  end

  def done?(%__MODULE__{step: step}), do: TaskType.done?(step)
end
