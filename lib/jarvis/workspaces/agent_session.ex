defmodule Jarvis.Workspaces.AgentSession do
  @moduledoc """
  A pi session working in a worktree. `task` is the task it last changed, shown
  as its focus; `inbox_cursor` is the last comment id it has been shown.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "agent_sessions" do
    field :pi_session_id, :string
    field :name, :string
    field :state, Ecto.Enum, values: [:idle, :working, :ended], default: :idle
    field :last_seen_at, :utc_datetime_usec
    field :inbox_cursor, :integer, default: 0
    belongs_to :project, Jarvis.Workspaces.Project
    belongs_to :worktree, Jarvis.Workspaces.Worktree
    belongs_to :task, Jarvis.Planning.Task
    timestamps(type: :utc_datetime_usec)
  end

  # A session that stopped heartbeating (pi crashed or the laptop slept) is shown as away.
  @away_after_seconds 180

  @doc "The state to show a human, accounting for sessions that stopped reporting."
  def presence(%__MODULE__{state: :ended}, _now), do: :ended

  def presence(%__MODULE__{state: state, last_seen_at: seen}, now) do
    if DateTime.diff(now, seen) > @away_after_seconds, do: :away, else: state
  end
end
