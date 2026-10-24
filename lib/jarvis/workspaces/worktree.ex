defmodule Jarvis.Workspaces.Worktree do
  @moduledoc "One checkout of a project, identified by its absolute path."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "worktrees" do
    field :path, :string
    field :name, :string
    field :branch, :string
    belongs_to :project, Jarvis.Workspaces.Project
    timestamps(type: :utc_datetime_usec)
  end

  def label(%__MODULE__{name: name, branch: nil}), do: name
  def label(%__MODULE__{name: name, branch: branch}), do: "#{name} (branch #{branch})"
end
