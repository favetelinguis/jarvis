defmodule Jarvis.PlanningTest do
  use Jarvis.DataCase, async: true

  import Jarvis.Fixtures

  alias Jarvis.Planning
  alias Jarvis.Planning.Markdown

  setup do
    repo = git_repo!()
    %{repo: repo, scope: agent_scope!(repo)}
  end

  describe "numbering" do
    test "goals are numbered per project and tasks per goal", %{scope: scope} do
      g1 = goal!(scope)
      g2 = goal!(scope)
      assert {g1.number, g2.number} == {1, 2}

      assert task!(scope, g1).number == 1
      assert task!(scope, g1).number == 2
      assert task!(scope, g2).number == 1
    end
  end

  describe "reads are confined to the scope's project" do
    test "another project's goal is not found", %{scope: scope} do
      goal!(scope)
      other = agent_scope!(git_repo!())

      assert {:error, :not_found} = Planning.fetch_goal(other, 1)
      assert {:error, :not_found} = Planning.fetch_task(other, 1, 1)
    end
  end

  describe "update_task/3" do
    test "changes only the given fields and records what changed", %{scope: scope} do
      goal = goal!(scope)
      task = task!(scope, goal, %{"requirements" => "- **R1** keep"})

      {:ok, updated} =
        Planning.update_task(scope, task, %{"status" => "ready", "sketch" => "lib/a.ex"})

      assert updated.status == :ready
      assert updated.requirements == "- **R1** keep"

      assert [%{summary: "Task 1.1: moved todo → ready; updated sketch"} | _] =
               Planning.list_events(scope)
    end

    test "claim takes the task for the caller's worktree and release frees it", %{
      repo: repo,
      scope: scope
    } do
      goal = goal!(scope)
      {:ok, claimed} = Planning.update_task(scope, task!(scope, goal), %{"claim" => true})
      assert claimed.worktree.path == repo

      {:ok, released} = Planning.update_task(human_scope(scope), claimed, %{"claim" => false})
      assert released.worktree_id == nil
    end

    test "the human cannot claim, having no worktree", %{scope: scope} do
      task = task!(scope, goal!(scope))

      assert {:error, changeset} =
               Planning.update_task(human_scope(scope), task, %{"claim" => true})

      assert %{claim: [_]} = errors_on(changeset)
    end

    test "rejects an unknown status", %{scope: scope} do
      task = task!(scope, goal!(scope))
      assert {:error, changeset} = Planning.update_task(scope, task, %{"status" => "blocked"})
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "the changed task becomes the agent session's focus", %{scope: scope} do
      task = task!(scope, goal!(scope))
      {:ok, _} = Planning.update_task(scope, task, %{"title" => "Renamed"})

      [session] = Jarvis.Workspaces.list_sessions(scope.project)
      assert session.task_id == task.id
    end
  end

  test "changes are broadcast to the project's viewers", %{scope: scope} do
    Jarvis.Workspaces.subscribe(scope.project.id)
    goal!(scope)
    assert_receive {:jarvis, :changed}
  end

  describe "take_inbox/1" do
    test "delivers the human's comments once, to the sessions concerned", %{
      repo: repo,
      scope: scope
    } do
      here = agent_scope!(repo, "here")
      elsewhere = agent_scope!(worktree!(repo, "other"), "elsewhere")
      human = human_scope(scope)

      goal = goal!(scope)
      mine = task!(here, goal, %{"claim" => true})
      open = task!(scope, goal)

      {:ok, _} = Planning.add_comment(human, goal, nil, %{"body" => "on the goal"})
      {:ok, _} = Planning.add_comment(human, goal, mine, %{"body" => "on a claimed task"})
      {:ok, _} = Planning.add_comment(human, goal, open, %{"body" => "on an open task"})
      {:ok, _} = Planning.add_comment(here, goal, mine, %{"body" => "agent note"})

      bodies = fn scope -> scope |> Planning.take_inbox() |> elem(1) |> Enum.map(& &1.body) end

      assert bodies.(here) == ["on the goal", "on a claimed task", "on an open task"]
      assert bodies.(elsewhere) == ["on the goal", "on an open task"]
      assert bodies.(agent_scope!(repo, "here")) == []
    end

    test "a new session is not shown comments made before it existed", %{repo: repo, scope: scope} do
      goal = goal!(scope)
      {:ok, _} = Planning.add_comment(human_scope(scope), goal, nil, %{"body" => "old"})

      assert {:ok, []} = Planning.take_inbox(agent_scope!(repo, "late"))
    end
  end

  describe "Markdown" do
    test "renders a task in the workflow's shape", %{scope: scope} do
      goal = goal!(scope, %{"title" => "Board"})

      task =
        task!(scope, goal, %{
          "title" => "Show tasks",
          "claim" => true,
          "requirements" => "- **R1** shall show",
          "open_questions" => "None."
        })

      {:ok, task} = Planning.fetch_task(scope, goal.number, task.number)
      text = Markdown.task(task)

      assert text =~ "# Task 1.1: Show tasks [todo]"
      assert text =~ "**Worktree:** #{scope.worktree.name} (branch main)"
      assert text =~ "**Requirements:**\n\n- **R1** shall show"
      assert text =~ "**Open questions:** None."
      refute text =~ "**Sketch:**"
    end
  end
end
