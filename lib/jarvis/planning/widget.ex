defmodule Jarvis.Planning.Widget do
  @moduledoc """
  One typed, structured piece of content in a section of a goal or task.

  `data` is what the agent wrote, validated against its kind in
  `Jarvis.Planning.Catalog`; `human` is what the human did with it (confirmed a
  requirement, answered a quiz, re-weighed criteria). The id is the widget id
  agents and comments refer to; it is never reused.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "widgets" do
    field :section, :string
    field :position, :integer
    field :kind, :string
    field :data, :map, default: %{}
    field :human, :map, default: %{}

    belongs_to :project, Jarvis.Workspaces.Project
    belongs_to :goal, Jarvis.Planning.Goal
    belongs_to :task, Jarvis.Planning.Task
    timestamps(type: :utc_datetime_usec)
  end
end
