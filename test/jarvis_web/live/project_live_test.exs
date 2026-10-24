defmodule JarvisWeb.ProjectLiveTest do
  use JarvisWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jarvis.Fixtures

  alias Jarvis.Planning

  setup do
    scope = agent_scope!(git_repo!())
    %{scope: scope}
  end

  defp board(conn, scope), do: live(conn, ~p"/projects/#{scope.project}")

  describe "task filtering" do
    setup %{scope: scope} do
      goal = goal!(scope)
      feature = task!(scope, goal, %{"title" => "Build it"})
      research = task!(scope, goal, %{"title" => "Look into it", "type" => "research"})

      {:ok, finished} =
        Planning.update_task(scope, task!(scope, goal, %{"type" => "research"}), %{
          "force_step" => "done"
        })

      %{goal: goal, feature: feature, research: research, finished: finished}
    end

    test "opens with All selected and shows every task with its type and step", %{
      conn: conn,
      scope: scope,
      feature: feature,
      research: research,
      finished: finished
    } do
      {:ok, view, _} = board(conn, scope)
      assert has_element?(view, "#filter-all[aria-pressed=true]")

      for task <- [feature, research, finished],
          do: assert(has_element?(view, "#task-#{task.id}"))

      assert has_element?(view, "#task-#{feature.id}", "Feature")
      assert has_element?(view, "#task-#{feature.id}", "Requirements")
      assert has_element?(view, "#task-#{research.id}", "Research")
    end

    test "Unfinished hides tasks in Done", %{
      conn: conn,
      scope: scope,
      feature: feature,
      finished: finished
    } do
      {:ok, view, _} = board(conn, scope)
      view |> element("#filter-unfinished") |> render_click()
      assert has_element?(view, "#task-#{feature.id}")
      refute has_element?(view, "#task-#{finished.id}")
      assert has_element?(view, "#filter-unfinished[aria-pressed=true]")
    end

    test "a type filter shows that type's steps to filter by", %{
      conn: conn,
      scope: scope,
      feature: feature,
      research: research,
      finished: finished
    } do
      {:ok, view, _} = board(conn, scope)
      refute has_element?(view, "#step-filter")
      view |> element("#type-research") |> render_click()

      refute has_element?(view, "#task-#{feature.id}")
      assert has_element?(view, "#task-#{research.id}")
      assert has_element?(view, "#step-filter #step-investigation")

      view |> element("#step-question") |> render_click()
      assert has_element?(view, "#task-#{research.id}")
      refute has_element?(view, "#task-#{finished.id}")

      view |> element("#type-research") |> render_click()
      refute has_element?(view, "#step-filter")
      assert has_element?(view, "#task-#{feature.id}")
    end

    test "a goal whose tasks do not match is hidden, but progress still counts them", %{
      conn: conn,
      scope: scope,
      goal: goal,
      finished: finished
    } do
      {:ok, view, _} = board(conn, scope)
      view |> element("#type-research") |> render_click()
      assert has_element?(view, "#goals-#{goal.id} [title='1 of 3 done']", "1/3")

      view |> element("#step-done") |> render_click()
      assert has_element?(view, "#task-#{finished.id}")

      view |> element("#type-learn") |> render_click()
      assert has_element?(view, "#no-matching-tasks")
      refute has_element?(view, "#goals-#{goal.id}")
    end

    test "keeps the filter across live changes", %{
      conn: conn,
      scope: scope,
      research: research,
      goal: goal
    } do
      {:ok, view, _} = board(conn, scope)
      view |> element("#type-research") |> render_click()

      {:ok, newer} =
        Planning.create_task(scope, goal, %{"title" => "Newer", "type" => "research"})

      assert has_element?(view, "#task-#{newer.id}")
      assert has_element?(view, "#type-research[aria-pressed=true]")

      Planning.update_task(scope, research, %{"force_step" => "done"})
      assert has_element?(view, "#goals-#{goal.id} [title='2 of 4 done']")
    end

    test "ignores unsupported filter values", %{conn: conn, scope: scope, feature: feature} do
      {:ok, view, _} = board(conn, scope)
      render_click(view, "type", %{"type" => "epic"})
      assert has_element?(view, "#task-#{feature.id}")
    end
  end

  test "shows the board guidance when there are no goals", %{conn: conn, scope: scope} do
    {:ok, view, _} = board(conn, scope)
    assert has_element?(view, "#no-goals")
  end

  test "lists goals newest first, including one created while open", %{conn: conn, scope: scope} do
    g1 = goal!(scope)
    task!(scope, g1)
    g2 = goal!(scope)
    task!(scope, g2)
    {:ok, view, _html} = live(conn, ~p"/projects/#{scope.project}")
    order = fn v -> Regex.scan(~r/id="(goals-\d+)"/, render(v)) |> Enum.map(&List.last/1) end
    assert order.(view) == ["goals-#{g2.id}", "goals-#{g1.id}"]

    g3 = goal!(scope)
    task!(scope, g3)
    _ = render(view)
    assert order.(view) == ["goals-#{g3.id}", "goals-#{g2.id}", "goals-#{g1.id}"]
  end

  test "there is no transcripts panel and transcript pages are not found", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = board(conn, scope)
    refute has_element?(view, "#transcripts-panel")
    assert get(conn, "/transcripts/5").status == 404
    assert post(conn, "/api/transcripts/sync").status == 404
  end

  test "lists projects and links to them", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#project-#{scope.project.id}")
  end

  test "shows a task as soon as an agent creates it", %{conn: conn, scope: scope} do
    {:ok, view, _html} = board(conn, scope)
    assert has_element?(view, "#no-goals")

    goal = goal!(scope)
    task = task!(scope, goal, %{"title" => "Live task"})

    assert has_element?(view, "#task-#{task.id}", "Live task")
    assert has_element?(view, "#sessions li[id^=session-]")
  end

  test "the activity feed describes a move in step names", %{conn: conn, scope: scope} do
    task = task!(scope, goal!(scope))
    {:ok, view, _} = board(conn, scope)
    Planning.update_task(scope, task, %{"force_step" => "design"})
    assert has_element?(view, "#events", "moved Requirements → Design")
  end

  test "a goal page shows its sections as widgets", %{conn: conn, scope: scope} do
    goal = goal!(scope, %{"title" => "Board"})
    widget!(scope, goal, nil, "intent", "prose", %{"text" => "See **agents**"})
    {:ok, view, _html} = live(conn, ~p"/projects/#{scope.project}/goals/1")
    assert has_element?(view, "#goal-intent strong", "agents")
    assert has_element?(view, "#goal-glossary", "Nothing here yet")
  end

  test "an unknown task redirects to the project", %{conn: conn, scope: scope} do
    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/projects/#{scope.project}/goals/9/tasks/1")

    assert to == ~p"/projects/#{scope.project}"
  end
end
