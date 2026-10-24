defmodule Jarvis.Scope do
  @moduledoc """
  Who is acting, and in which project.

  Agents act through the API as an agent session inside a worktree; the human
  acts through the web UI with only a project. Planning functions take a scope
  first so every change is attributed and confined to one project.
  """

  alias Jarvis.Workspaces.{AgentSession, Project, Worktree}

  defstruct [:project, :worktree, :agent_session]

  @type t :: %__MODULE__{
          project: Project.t(),
          worktree: Worktree.t() | nil,
          agent_session: AgentSession.t() | nil
        }

  def for_human(%Project{} = project), do: %__MODULE__{project: project}

  def agent?(%__MODULE__{agent_session: session}), do: not is_nil(session)
end
