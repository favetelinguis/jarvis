defmodule Jarvis.Planning.Comment do
  @moduledoc """
  A note on a goal or task. An anchored comment also points at a widget, or at
  one part of it; `anchor_label` and `anchor_text` keep what it pointed at, so
  the comment still makes sense after the widget or part is gone.

  Human comments without an anchor reach agents at the start of their next
  turn (the inbox). Comments with `deliver` set wake the listening session and
  are marked `delivered_at` once it has taken them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "comments" do
    field :author, Ecto.Enum, values: [:human, :agent, :system]
    field :body, :string
    field :part, :string
    field :anchor_label, :string
    field :anchor_text, :string
    field :deliver, :boolean, default: false
    field :delivered_at, :utc_datetime_usec
    belongs_to :goal, Jarvis.Planning.Goal
    belongs_to :task, Jarvis.Planning.Task
    belongs_to :widget, Jarvis.Planning.Widget
    belongs_to :reply_to, __MODULE__
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

  def anchored?(%__MODULE__{anchor_label: label}), do: not is_nil(label)
end
