defmodule Jarvis.Workspaces.Project do
  @moduledoc "A repository, shared by all of its worktrees. Its key is the absolute git common dir."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "projects" do
    field :key, :string
    field :name, :string
    has_many :worktrees, Jarvis.Workspaces.Worktree
    timestamps(type: :utc_datetime_usec)
  end
end
