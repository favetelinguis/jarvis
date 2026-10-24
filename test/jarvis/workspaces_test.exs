defmodule Jarvis.WorkspacesTest do
  use Jarvis.DataCase, async: true

  import Jarvis.Fixtures

  alias Jarvis.Workspaces
  alias Jarvis.Workspaces.AgentSession

  describe "register/1" do
    test "worktrees of one repository share a project" do
      repo = git_repo!()
      other = worktree!(repo, "feature")

      main = agent_scope!(repo)
      feature = agent_scope!(Path.join(other, "."))

      assert main.project.id == feature.project.id
      assert main.project.name == Path.basename(repo)
      assert main.worktree.branch == "main"
      assert feature.worktree.branch == "feature"
      refute main.worktree.id == feature.worktree.id
    end

    test "a subdirectory belongs to the worktree it is in" do
      repo = git_repo!()
      File.mkdir_p!(Path.join(repo, "lib/deep"))

      assert agent_scope!(Path.join(repo, "lib/deep")).worktree.path ==
               agent_scope!(repo).worktree.path
    end

    test "a directory outside git is a project of its own" do
      dir = Path.join(System.tmp_dir!(), "jarvis-plain-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      scope = agent_scope!(dir)
      assert scope.project.key == dir
      assert scope.worktree.branch == nil
    end

    test "a Codex tool call without a session id acts as the agent's live session there" do
      repo = git_repo!()

      {:ok, hooked} =
        Workspaces.register(%{"cwd" => repo, "session_id" => "codex-1", "agent" => "codex"})

      {:ok, called} = Workspaces.register(%{"cwd" => repo, "agent" => "codex"})
      assert called.agent_session.id == hooked.agent_session.id
      assert called.agent_session.agent == :codex
      assert called.worktree.id == hooked.worktree.id
    end

    test "an agent without any session gets a stand-in session, and pi still needs an id" do
      repo = git_repo!()
      assert {:ok, scope} = Workspaces.register(%{"cwd" => repo, "agent" => "copilot"})
      assert scope.agent_session.agent == :copilot
      assert {:error, %Ecto.Changeset{}} = Workspaces.register(%{"cwd" => repo})
      assert {:error, %Ecto.Changeset{}} = Workspaces.register(%{"cwd" => repo, "agent" => "vim"})
    end

    test "only pi sessions are woken; Codex and Copilot CLI hear comments at their next turn" do
      alias Jarvis.Workspaces.AgentSession
      assert AgentSession.listening(%AgentSession{agent: :pi})
      assert AgentSession.listening(%AgentSession{agent: :codex}) == :next_turn
      assert AgentSession.listening(nil) == false
    end

    test "registering the same session again updates it instead of adding one" do
      repo = git_repo!()
      first = agent_scope!(repo, "same")
      second = agent_scope!(repo, "same")

      assert first.agent_session.id == second.agent_session.id
    end

    test "rejects a missing or relative cwd" do
      assert {:error, :invalid_cwd} =
               Workspaces.register(%{"cwd" => "relative", "session_id" => "s"})

      assert {:error, :invalid_cwd} =
               Workspaces.register(%{"cwd" => "/does/not/exist", "session_id" => "s"})

      assert {:error, %Ecto.Changeset{}} = Workspaces.register(%{"cwd" => "/tmp"})
    end
  end

  test "a session that stopped reporting shows as away" do
    now = DateTime.utc_now()
    session = %AgentSession{state: :working, last_seen_at: now}

    assert AgentSession.presence(session, now) == :working
    assert AgentSession.presence(session, DateTime.add(now, 181)) == :away
    assert AgentSession.presence(%{session | state: :ended}, now) == :ended
  end
end
