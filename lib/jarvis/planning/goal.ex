defmodule Jarvis.Planning.Goal do
  @moduledoc """
  A goal: one problem worth solving, cut into tasks. Its sections (Intent,
  Scope, Glossary, Decisions) are widgets. Numbered per project, and the number
  never changes or gets reused.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "goals" do
    field :number, :integer
    field :title, :string

    belongs_to :project, Jarvis.Workspaces.Project
    has_many :tasks, Jarvis.Planning.Task, preload_order: [asc: :number]
    has_many :comments, Jarvis.Planning.Comment, preload_order: [asc: :id]
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:title], empty_values: [])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
  end
end
