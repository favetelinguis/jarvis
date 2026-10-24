defmodule JarvisWeb.ProjectLiveTest do
  use JarvisWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jarvis.Fixtures

  alias Jarvis.Planning

  setup do
    scope = agent_scope!(git_repo!())
    %{scope: scope}
  end

  describe "task filtering" do
    test "opens the board with All selected", %{conn: conn, scope: scope} do
      {_goal, tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")

      assert_selected(view, "all")
      for task <- tasks, do: assert(has_element?(view, "#task-#{task.id}"))
    end

    test "offers all five filter choices", %{conn: conn, scope: scope} do
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      assert has_element?(view, "#task-filter[role=group][aria-label]")

      for {filter, label} <- [
            {"all", "All"},
            {"unfinished", "Unfinished"},
            {"todo", "Todo"},
            {"ready", "Ready"},
            {"done", "Done"}
          ] do
        assert has_element?(view, "#filter-#{filter}[type=button]", label)
        view |> element("#filter-#{filter}") |> render_click()
        assert_selected(view, filter)
      end
    end

    test "All shows tasks of every status", %{conn: conn, scope: scope} do
      {goal, tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()
      view |> element("#filter-all") |> render_click()

      assert_selected(view, "all")
      assert has_element?(view, "#goals-#{goal.id}")

      for task <- tasks do
        assert has_element?(view, "#task-#{task.id}") == task.status in [:todo, :ready, :done]
      end
    end

    test "Unfinished shows todo and ready tasks only", %{conn: conn, scope: scope} do
      {goal, tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()
      view |> element("#filter-unfinished") |> render_click()

      assert_selected(view, "unfinished")
      assert has_element?(view, "#goals-#{goal.id}")

      for task <- tasks do
        assert has_element?(view, "#task-#{task.id}") == task.status in [:todo, :ready]
      end
    end

    test "Todo shows todo tasks only", %{conn: conn, scope: scope} do
      {goal, tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()
      view |> element("#filter-todo") |> render_click()

      assert_selected(view, "todo")
      assert has_element?(view, "#goals-#{goal.id}")

      for task <- tasks do
        assert has_element?(view, "#task-#{task.id}") == task.status in [:todo]
      end
    end

    test "Ready shows ready tasks only", %{conn: conn, scope: scope} do
      {goal, tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()
      view |> element("#filter-ready") |> render_click()

      assert_selected(view, "ready")
      assert has_element?(view, "#goals-#{goal.id}")

      for task <- tasks do
        assert has_element?(view, "#task-#{task.id}") == task.status in [:ready]
      end
    end

    test "Done shows done tasks only", %{conn: conn, scope: scope} do
      {goal, tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()
      view |> element("#filter-done") |> render_click()

      assert_selected(view, "done")
      assert has_element?(view, "#goals-#{goal.id}")

      for task <- tasks do
        assert has_element?(view, "#task-#{task.id}") == task.status in [:done]
      end
    end

    test "hides a goal whose only task does not match", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      task = task!(scope, goal, %{"status" => "done"})
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-unfinished") |> render_click()

      refute has_element?(view, "#goals-#{goal.id}")
      refute has_element?(view, "#task-#{task.id}")
      assert has_element?(view, "#no-matching-tasks", "No matching tasks")
      refute has_element?(view, "#no-goals")
    end

    test "shows a goal with one matching task", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      task = task!(scope, goal)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-unfinished") |> render_click()

      assert has_element?(view, "#goals-#{goal.id} #task-#{task.id}")
      refute has_element?(view, "#no-matching-tasks")
      refute has_element?(view, "#no-goals")
    end

    test "shows every matching task without truncation", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      tasks = for _ <- 1..3, do: task!(scope, goal)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-todo") |> render_click()

      for task <- tasks, do: assert(has_element?(view, "#task-#{task.id}"))
    end

    test "All hides taskless goals alongside matching goals", %{conn: conn, scope: scope} do
      empty_goal = goal!(scope)
      goal = goal!(scope)
      task = task!(scope, goal)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")

      refute has_element?(view, "#goals-#{empty_goal.id}")
      assert has_element?(view, "#goals-#{goal.id} #task-#{task.id}")
      refute has_element?(view, "#no-matching-tasks")
    end

    test "shows no matching tasks when all goals are taskless", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")

      refute has_element?(view, "#goals-#{goal.id}")
      assert has_element?(view, "#no-matching-tasks", "No matching tasks")
      refute has_element?(view, "#no-goals")
      assert_selected(view, "all")
    end

    test "keeps no-goals guidance for every filter on a project without goals", %{
      conn: conn,
      scope: scope
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")

      for filter <- ~w(all unfinished todo ready done) do
        view |> element("#filter-#{filter}") |> render_click()
        assert has_element?(view, "#no-goals code", "/specify")
        refute has_element?(view, "#no-matching-tasks")
        assert_selected(view, filter)
      end
    end

    test "keeps overall progress based on hidden tasks", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      done = task!(scope, goal, %{"status" => "done"})
      todo = task!(scope, goal)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-todo") |> render_click()

      assert has_element?(view, "#goals-#{goal.id} [title='1 of 2 done']", "1/2")
      assert has_element?(view, "#task-#{todo.id}")
      refute has_element?(view, "#task-#{done.id}")
    end

    test "removes the last matching task and goal on a live status change", %{
      conn: conn,
      scope: scope
    } do
      goal = goal!(scope)
      task = task!(scope, goal, %{"status" => "ready"})
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-unfinished") |> render_click()
      assert has_element?(view, "#goals-#{goal.id} #task-#{task.id}")

      assert {:ok, _} = Planning.update_task(scope, task, %{"status" => "done"})

      refute has_element?(view, "#task-#{task.id}")
      refute has_element?(view, "#goals-#{goal.id}")
      assert has_element?(view, "#no-matching-tasks", "No matching tasks")
      refute has_element?(view, "#no-goals")
      assert_selected(view, "unfinished")
    end

    test "adds a newly matching task and goal on a live status change", %{
      conn: conn,
      scope: scope
    } do
      goal = goal!(scope)
      task = task!(scope, goal, %{"status" => "done"})
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-unfinished") |> render_click()
      assert has_element?(view, "#no-matching-tasks")

      assert {:ok, _} = Planning.update_task(scope, task, %{"status" => "todo"})

      assert has_element?(view, "#goals-#{goal.id} #task-#{task.id}")
      refute has_element?(view, "#no-matching-tasks")
      assert_selected(view, "unfinished")
    end

    test "keeps other matching tasks after a live status change", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      ready = task!(scope, goal, %{"status" => "ready"})
      todo = task!(scope, goal)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-unfinished") |> render_click()

      assert {:ok, _} = Planning.update_task(scope, ready, %{"status" => "done"})

      refute has_element?(view, "#task-#{ready.id}")
      assert has_element?(view, "#goals-#{goal.id} #task-#{todo.id}")
      refute has_element?(view, "#no-matching-tasks")
      assert_selected(view, "unfinished")
    end

    test "keeps goal membership independent across live status changes", %{
      conn: conn,
      scope: scope
    } do
      first_goal = goal!(scope)
      second_goal = goal!(scope)
      ready = task!(scope, first_goal, %{"status" => "ready"})
      done = task!(scope, second_goal, %{"status" => "done"})
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      assert has_element?(view, "#goals-#{first_goal.id} #task-#{ready.id}")
      assert has_element?(view, "#goals-#{second_goal.id} #task-#{done.id}")

      view |> element("#filter-unfinished") |> render_click()
      assert has_element?(view, "#goals-#{first_goal.id} #task-#{ready.id}")
      refute has_element?(view, "#goals-#{second_goal.id}")
      refute has_element?(view, "#task-#{done.id}")

      assert {:ok, _} = Planning.update_task(scope, ready, %{"status" => "done"})

      refute has_element?(view, "#goals > section")
      refute has_element?(view, "#task-#{ready.id}")
      assert has_element?(view, "#no-matching-tasks")

      assert {:ok, _} = Planning.update_task(scope, done, %{"status" => "todo"})

      refute has_element?(view, "#goals-#{first_goal.id}")
      refute has_element?(view, "#task-#{ready.id}")
      assert has_element?(view, "#goals-#{second_goal.id} #task-#{done.id}")
      refute has_element?(view, "#no-matching-tasks")
      assert_selected(view, "unfinished")
    end

    test "shows a newly created matching task without reloading", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-todo") |> render_click()
      assert has_element?(view, "#no-matching-tasks")

      assert {:ok, task} = Planning.create_task(scope, goal, %{"title" => "New todo"})

      assert has_element?(view, "#goals-#{goal.id} #task-#{task.id}", "New todo")
      refute has_element?(view, "#no-matching-tasks")
      assert_selected(view, "todo")
    end

    test "refreshes task titles without resetting the filter", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      task = task!(scope, goal, %{"status" => "ready", "title" => "Old title"})
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()

      assert {:ok, _} = Planning.update_task(scope, task, %{"title" => "New title"})

      assert has_element?(view, "#task-#{task.id}", "New title")
      refute has_element?(view, "#task-#{task.id}", "Old title")
      assert_selected(view, "ready")
    end

    test "refreshes task claims without resetting the filter", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      task = task!(scope, goal, %{"status" => "ready"})
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()

      refute has_element?(
               view,
               "#task-#{task.id} [title='#{Jarvis.Workspaces.Worktree.label(scope.worktree)}']"
             )

      assert {:ok, _} = Planning.update_task(scope, task, %{"claim" => true})

      assert has_element?(
               view,
               "#task-#{task.id} [title='#{Jarvis.Workspaces.Worktree.label(scope.worktree)}']",
               scope.worktree.name
             )

      assert_selected(view, "ready")
    end

    test "refreshes unrelated board information without resetting the filter", %{
      conn: conn,
      scope: scope
    } do
      {goal, _tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()

      assert {:ok, _} = Planning.add_comment(scope, goal, nil, %{"body" => "Board note"})

      assert has_element?(view, "#events li[id^=events-]", "commented on Goal #{goal.number}")
      assert_selected(view, "ready")
    end

    test "resets Ready to All after a reload", %{conn: conn, scope: scope} do
      {_goal, tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()
      assert_selected(view, "ready")

      {:ok, reloaded, _} = live(conn, ~p"/projects/#{scope.project}")

      assert_selected(reloaded, "all")
      for task <- tasks, do: assert(has_element?(reloaded, "#task-#{task.id}"))
    end

    test "resets Ready to All after leaving and returning", %{conn: conn, scope: scope} do
      {goal, tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()
      assert_selected(view, "ready")
      goal_path = ~p"/projects/#{scope.project}/goals/#{goal.number}"

      {:ok, detail, _} =
        view
        |> element("#goals-#{goal.id} > a")
        |> render_click()
        |> follow_redirect(conn, goal_path)

      board_path = ~p"/projects/#{scope.project}"

      {:ok, returned, _} =
        detail
        |> element("a[href='#{board_path}']")
        |> render_click()
        |> follow_redirect(conn, board_path)

      assert_selected(returned, "all")
      for task <- tasks, do: assert(has_element?(returned, "#task-#{task.id}"))
    end

    test "filter selection leaves task contents status and claim unchanged", %{
      conn: conn,
      scope: scope
    } do
      goal = goal!(scope)

      task =
        task!(scope, goal, %{
          "title" => "Keep me",
          "status" => "ready",
          "claim" => true,
          "requirements" => "Keep requirements",
          "sketch" => "Keep sketch",
          "tests" => "Keep tests"
        })

      assert {:ok, original} = Planning.fetch_task(scope, goal.number, task.number)
      events = Planning.list_events(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")

      for filter <- ~w(all unfinished todo ready done) do
        view |> element("#filter-#{filter}") |> render_click()
        assert {:ok, ^original} = Planning.fetch_task(scope, goal.number, task.number)
        assert Planning.list_events(scope) == events
      end
    end

    test "goal detail remains unfiltered when reached from a filtered board", %{
      conn: conn,
      scope: scope
    } do
      goal = goal!(scope)
      tasks = [task!(scope, goal), task!(scope, goal, %{"status" => "done"})]
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-todo") |> render_click()
      goal_path = ~p"/projects/#{scope.project}/goals/#{goal.number}"

      {:ok, detail, _} =
        view
        |> element("#goals-#{goal.id} > a")
        |> render_click()
        |> follow_redirect(conn, goal_path)

      for task <- tasks, do: assert(has_element?(detail, "#goal-tasks #task-#{task.id}"))
      refute has_element?(detail, "#task-filter")
    end

    test "task detail remains unfiltered when reached from a filtered board", %{
      conn: conn,
      scope: scope
    } do
      goal = goal!(scope)

      task =
        task!(scope, goal, %{
          "status" => "ready",
          "claim" => true,
          "requirements" => "Original requirements"
        })

      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()
      task_path = ~p"/projects/#{scope.project}/goals/#{goal.number}/tasks/#{task.number}"

      {:ok, detail, _} =
        view
        |> element("#task-#{task.id} a")
        |> render_click()
        |> follow_redirect(conn, task_path)

      assert has_element?(detail, "#task-requirements", "Original requirements")
      assert has_element?(detail, "#status-ready")
      assert has_element?(detail, "#release-claim")

      assert has_element?(
               detail,
               "header [title='#{Jarvis.Workspaces.Worktree.label(scope.worktree)}']",
               scope.worktree.name
             )

      refute has_element?(detail, "#task-filter")
    end

    test "updates overall progress when a hidden task changes", %{conn: conn, scope: scope} do
      goal = goal!(scope)
      ready = task!(scope, goal, %{"status" => "ready"})
      hidden = task!(scope, goal)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()
      assert has_element?(view, "#goals-#{goal.id} [title='0 of 2 done']", "0/2")
      refute has_element?(view, "#task-#{hidden.id}")

      assert {:ok, _} = Planning.update_task(scope, hidden, %{"status" => "done"})

      assert has_element?(view, "#goals-#{goal.id} [title='1 of 2 done']", "1/2")
      assert has_element?(view, "#task-#{ready.id}")
      refute has_element?(view, "#task-#{hidden.id}")
      assert_selected(view, "ready")
    end

    test "ignores missing and unsupported filter values", %{conn: conn, scope: scope} do
      {_goal, tasks} = status_tasks(scope)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")
      view |> element("#filter-ready") |> render_click()

      for params <- [%{}, %{"filter" => "unknown"}, %{"filter" => nil}, %{"filter" => ["ready"]}] do
        render_click(view, "filter", params)
        assert_selected(view, "ready")

        for task <- tasks do
          assert has_element?(view, "#task-#{task.id}") == (task.status == :ready)
        end
      end
    end
  end

  defp status_tasks(scope) do
    goal = goal!(scope)
    tasks = for status <- ~w(todo ready done), do: task!(scope, goal, %{"status" => status})
    {goal, tasks}
  end

  defp assert_selected(view, selected) do
    assert has_element?(view, "#task-filter button[aria-pressed=true]")

    for filter <- ~w(all unfinished todo ready done) do
      pressed = to_string(filter == selected)
      assert has_element?(view, "#filter-#{filter}[aria-pressed=#{pressed}]")
    end
  end

  test "lists projects and links to them", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#project-#{scope.project.id}")
  end

  test "shows a task as soon as an agent creates it", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/projects/#{scope.project}")
    assert has_element?(view, "#no-goals")

    goal = goal!(scope)
    task = task!(scope, goal, %{"title" => "Live task"})

    assert has_element?(view, "#task-#{task.id}", "Live task")
    assert has_element?(view, "#sessions li[id^=session-]")
  end

  test "the human moves a task, releases it, and comments", %{conn: conn, scope: scope} do
    goal = goal!(scope)
    task = task!(scope, goal, %{"claim" => true, "requirements" => "- **R1** shall"})

    {:ok, view, _html} = live(conn, ~p"/projects/#{scope.project}/goals/1/tasks/1")
    assert has_element?(view, "#task-requirements")

    view |> element("#status-done") |> render_click()
    assert {:ok, %{status: :done}} = Planning.fetch_task(scope, 1, 1)

    view |> element("#release-claim") |> render_click()
    assert {:ok, %{worktree_id: nil}} = Planning.fetch_task(scope, 1, 1)

    view |> form("#comment-form", comment: %{body: "Looks good"}) |> render_submit()
    assert has_element?(view, "#comments li[id^=comment-]", "Looks good")

    assert {:ok, [%{body: "Looks good", task_id: task_id}]} = Planning.take_inbox(scope)
    assert task_id == task.id
  end

  test "a goal page shows its sections", %{conn: conn, scope: scope} do
    goal!(scope, %{"title" => "Board", "intent" => "See **agents**"})
    {:ok, view, _html} = live(conn, ~p"/projects/#{scope.project}/goals/1")
    assert has_element?(view, "#goal-intent strong", "agents")
  end

  test "an unknown task redirects to the project", %{conn: conn, scope: scope} do
    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/projects/#{scope.project}/goals/9/tasks/1")

    assert to == ~p"/projects/#{scope.project}"
  end
end
