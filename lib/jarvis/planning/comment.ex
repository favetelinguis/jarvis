defmodule Jarvis.Planning.Comment do
  @moduledoc """
  A note on a goal, or on one of its tasks. Human comments are delivered to the
  agent sessions concerned at the start of their next turn.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "comments" do
    field :author, Ecto.Enum, values: [:human, :agent]
    field :body, :string
    belongs_to :goal, Jarvis.Planning.Goal
    belongs_to :task, Jarvis.Planning.Task
    belongs_to :agent_session, Jarvis.Workspaces.AgentSession
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, max: 20_000)
  end
end
