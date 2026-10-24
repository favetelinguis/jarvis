defmodule Jarvis.Transcripts.Transcript do
  @moduledoc """
  The mirror of one agent session file. `byte_offset` is how far the file has
  been read; `last_line_offset` and `last_line_hash` identify the last line
  read, so a rewritten file is detected and read again from the start.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "transcripts" do
    field :harness, Ecto.Enum, values: [:pi, :codex]
    field :external_id, :string
    field :path, :string
    field :cwd, :string
    field :title, :string
    field :line_count, :integer, default: 0
    field :byte_offset, :integer, default: 0
    field :last_line_offset, :integer, default: 0
    field :last_line_hash, :binary
    field :last_entry_at, :utc_datetime_usec
    belongs_to :project, Jarvis.Workspaces.Project
    belongs_to :worktree, Jarvis.Workspaces.Worktree
    timestamps(type: :utc_datetime_usec)
  end
end
