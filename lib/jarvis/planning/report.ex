defmodule Jarvis.Planning.Report do
  @moduledoc """
  A turn report: what one agent session changed on one goal (task `nil`) or
  task during one agent turn. It is shown once the turn has ended
  (`closed_at`) and moves to the history when the human reads it (`read_at`).

  `entries` is `%{"items" => [entry]}`, one entry per widget, created task, or
  move, in order. An entry has `"action"` (`added`, `updated`, `moved`,
  `deleted`, `stale`, `task_created`, `step`), and for widgets `"widget"`,
  `"kind"`, `"section"`, `"before"` and `"after"` (data maps, `nil` when absent),
  and `"reasons"` (what the agent said in the calls that made the change).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "reports" do
    field :turn, :integer
    field :entries, :map, default: %{}
    field :needs, :string
    field :closed_at, :utc_datetime_usec
    field :read_at, :utc_datetime_usec

    belongs_to :project, Jarvis.Workspaces.Project
    belongs_to :goal, Jarvis.Planning.Goal
    belongs_to :task, Jarvis.Planning.Task
    belongs_to :agent_session, Jarvis.Workspaces.AgentSession
    timestamps(type: :utc_datetime_usec)
  end

  def items(%__MODULE__{entries: entries}), do: entries["items"] || []

  @doc "Widget ids the report changed (not removed), to mark them on the page."
  def widget_ids(report) do
    for %{"widget" => id, "action" => a} <- items(report), a != "deleted", do: id
  end
end
