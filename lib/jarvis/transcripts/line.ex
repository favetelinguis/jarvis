defmodule Jarvis.Transcripts.Line do
  @moduledoc """
  One line of a session file. `line` holds the exact bytes, which is what makes
  a restored file identical to the original; `role` and `text` are the
  harness-neutral reading of it used for display.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @roles [:user, :assistant, :tool_call, :tool_result, :system, :meta]

  @primary_key false
  schema "transcript_lines" do
    belongs_to :transcript, Jarvis.Transcripts.Transcript, primary_key: true
    field :seq, :integer, primary_key: true
    field :line, :binary
    field :role, Ecto.Enum, values: @roles
    field :text, :string
    field :at, :utc_datetime_usec
  end

  def roles, do: @roles
end
