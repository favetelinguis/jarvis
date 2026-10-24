defmodule Jarvis.Planning.Event do
  @moduledoc "One line in a project's activity feed: who changed what."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "events" do
    field :actor, Ecto.Enum, values: [:human, :agent]
    field :summary, :string
    belongs_to :project, Jarvis.Workspaces.Project
    belongs_to :goal, Jarvis.Planning.Goal
    belongs_to :task, Jarvis.Planning.Task
    belongs_to :agent_session, Jarvis.Workspaces.AgentSession
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
