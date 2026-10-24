defmodule JarvisWeb.TaskLiveTest do
  use JarvisWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jarvis.Fixtures

  alias Jarvis.Planning

  setup do
    scope = agent_scope!(git_repo!())
    goal = goal!(scope)
    task = task!(scope, goal, %{"title" => "Show it", "claim" => true})
    %{scope: scope, goal: goal, task: task}
  end

  defp open(conn, scope, n \\ 1),
    do: live(conn, ~p"/projects/#{scope.project}/goals/1/tasks/#{n}")

  describe "the lifecycle graph" do
    test "shows the type, the current step, and the next steps", %{conn: conn, scope: scope} do
      {:ok, view, _} = open(conn, scope)
      assert has_element?(view, "header", "Feature")
      assert has_element?(view, "#step-requirements[data-state=current]")
      assert has_element?(view, "#step-design[data-state=next]")
      assert has_element?(view, "#step-done[data-state=other]")
      refute has_element?(view, "[data-state=previous]")
    end

    test "marks where the task came from after a move", %{conn: conn, scope: scope, task: task} do
      {:ok, _} = Planning.update_task(scope, task, %{"force_step" => "design"})
      {:ok, view, _} = open(conn, scope)
      assert has_element?(view, "#step-design[data-state=current]")
      assert has_element?(view, "#step-requirements[data-state=previous]")
      assert has_element?(view, "#step-implementation[data-state=next]")
      assert has_element?(view, "#step-requirements", "came from")
    end

    test "lists each move with its mover, and the agent's command", %{
      conn: conn,
      scope: scope,
      task: task
    } do
      {:ok, _} = Planning.update_task(scope, task, %{"force_step" => "design"})
      {:ok, view, _} = open(conn, scope)
      assert has_element?(view, "#transition-approve-design", "/design-review")
      assert has_element?(view, "#transition-requirements-question", "/design")
      refute has_element?(view, "#transition-approve-design button")
    end

    test "the human's move is a button that is disabled with the reason until the condition holds",
         %{conn: conn, scope: scope, goal: goal, task: task} do
      widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
      {:ok, view, _} = open(conn, scope)

      assert has_element?(view, "#transition-approve-requirements button[disabled]")
      assert has_element?(view, "#transition-approve-requirements", "R1 not confirmed")

      view |> element("#confirm-#{hd(Planning.list_widgets(goal, task)).id}") |> render_click()
      refute has_element?(view, "#transition-approve-requirements button[disabled]")

      view |> element("#transition-approve-requirements button") |> render_click()
      assert has_element?(view, "#step-design[data-state=current]")
      assert {:ok, %{step: "design"}} = Planning.fetch_task(scope, 1, 1)
    end

    test "Done ends the lifecycle", %{conn: conn, scope: scope, task: task} do
      {:ok, _} = Planning.update_task(scope, task, %{"force_step" => "done"})
      {:ok, view, _} = open(conn, scope)
      assert has_element?(view, "#lifecycle", "This step ends the lifecycle")
    end

    test "each type shows its own sections", %{conn: conn, scope: scope, goal: goal} do
      task!(scope, goal, %{"type" => "pr_review", "title" => "Review"})
      {:ok, view, _} = open(conn, scope, 2)
      assert has_element?(view, "#section-pull_request")
      assert has_element?(view, "#section-verdict")
      refute has_element?(view, "#section-requirements")
      assert has_element?(view, "#step-intake[data-state=current]")
    end
  end

  describe "requirement cards" do
    setup %{scope: scope, goal: goal, task: task} do
      widget =
        widget!(
          scope,
          goal,
          task,
          "requirements",
          "requirement",
          Map.merge(requirement("R1"), %{"pattern" => "event", "trigger" => "x happens"})
        )

      %{widget: widget}
    end

    test "show the pattern and confirm and unconfirm", %{conn: conn, scope: scope, widget: widget} do
      {:ok, view, _} = open(conn, scope)
      assert has_element?(view, "#widget-#{widget.id}", "When")
      assert has_element?(view, "#widget-#{widget.id}", "x happens")

      view |> element("#confirm-#{widget.id}") |> render_click()
      assert has_element?(view, "#widget-#{widget.id}", "Confirmed")
      assert {:ok, %{human: %{"confirmed" => true}}} = Planning.fetch_widget(scope, widget.id)

      view |> element("#confirm-#{widget.id}") |> render_click()
      assert {:ok, %{human: human}} = Planning.fetch_widget(scope, widget.id)
      refute human["confirmed"]
    end

    test "an agent changing the text clears the confirmation live", %{
      conn: conn,
      scope: scope,
      goal: goal,
      task: task,
      widget: widget
    } do
      {:ok, view, _} = open(conn, scope)
      view |> element("#confirm-#{widget.id}") |> render_click()

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{"op" => "update", "id" => widget.id, "data" => requirement("R1", "something else")}
        ])

      refute has_element?(view, "#widget-#{widget.id}", "Confirmed")
      assert has_element?(view, "#widget-#{widget.id}", "something else")
    end
  end

  describe "comments on widgets and their parts" do
    setup %{scope: scope, goal: goal, task: task} do
      %{widget: widget!(scope, goal, task, "examples", "examples")}
    end

    test "the human comments on a part; the thread appears at that part and the agent is woken",
         %{conn: conn, scope: scope, widget: widget} do
      {:ok, view, _} = open(conn, scope)
      view |> element("#row-#{widget.id}-r2 button[phx-value-part='row:r2']") |> render_click()
      assert has_element?(view, "#composer-#{widget.id}", "Examples table W#{widget.id} · Row 2")

      view |> form("#composer-#{widget.id}", body: "Why rejected?") |> render_submit()

      refute has_element?(view, "#composer-#{widget.id}")
      assert has_element?(view, "#thread-#{widget.id}-row\\:r2", "Why rejected?")

      assert has_element?(
               view,
               "#thread-status-#{widget.id}-row\\:r2",
               "The agent is being woken"
             )

      assert {:ok, [%{part: "row:r2", body: "Why rejected?"}]} = Planning.take_wake(scope)
    end

    test "says so when nobody listens", %{conn: conn, scope: scope, widget: widget, task: task} do
      Jarvis.Repo.update_all(Jarvis.Workspaces.AgentSession, set: [state: :ended])
      {:ok, view, _} = open(conn, scope)
      view |> element("#widget-#{widget.id} header button") |> render_click()
      view |> form("#composer-#{widget.id}", body: "Hello?") |> render_submit()
      assert has_element?(view, "#thread-status-#{widget.id}-widget", "No agent listening")
      _ = task
    end

    test "the count shows on the comment button and replies join the thread live", %{
      conn: conn,
      scope: scope,
      goal: goal,
      task: task,
      widget: widget
    } do
      {:ok, view, _} = open(conn, scope)
      view |> element("#widget-#{widget.id} header button") |> render_click()
      view |> form("#composer-#{widget.id}", body: "Thoughts?") |> render_submit()
      assert has_element?(view, "#widget-#{widget.id} header button", "1")

      [asked] = Jarvis.Repo.all(Jarvis.Planning.Comment)

      {:ok, _} =
        Planning.add_comment(scope, goal, task, %{"body" => "It is fine.", "reply_to" => asked.id})

      assert has_element?(view, "#thread-#{widget.id}-widget", "It is fine.")
    end

    test "a thread shows when the agent updated its widget", %{
      conn: conn,
      scope: scope,
      goal: goal,
      task: task,
      widget: widget
    } do
      {:ok, view, _} = open(conn, scope)
      view |> element("#widget-#{widget.id} header button") |> render_click()
      view |> form("#composer-#{widget.id}", body: "Add a row") |> render_submit()

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{"op" => "update", "id" => widget.id, "data" => widget.data}
        ])

      assert has_element?(view, "#thread-#{widget.id}-widget", "Widget updated")
    end

    test "a comment on a part the agent removed stays, marked 'Part removed'", %{
      conn: conn,
      scope: scope,
      goal: goal,
      task: task,
      widget: widget
    } do
      {:ok, _} =
        Planning.add_comment(human_scope(scope), goal, task, %{
          "body" => "about r3",
          "widget" => widget.id,
          "part" => "row:r3"
        })

      data = update_in(widget.data, ["rows"], &Enum.reject(&1, fn r -> r["id"] == "r3" end))

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{"op" => "update", "id" => widget.id, "data" => data}
        ])

      {:ok, view, _} = open(conn, scope)
      assert has_element?(view, "#thread-#{widget.id}-row\\:r3", "Part removed")
      assert has_element?(view, "#thread-#{widget.id}-row\\:r3", "about r3")
    end

    test "a comment on a deleted widget is listed under Removed anchors", %{
      conn: conn,
      scope: scope,
      goal: goal,
      task: task,
      widget: widget
    } do
      {:ok, comment} =
        Planning.add_comment(human_scope(scope), goal, task, %{
          "body" => "bye",
          "widget" => widget.id
        })

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [%{"op" => "delete", "id" => widget.id}])

      {:ok, view, _} = open(conn, scope)
      assert has_element?(view, "#removed-#{comment.id}", "Widget removed")
      assert has_element?(view, "#removed-#{comment.id}", "bye")
    end

    test "Question on a requirement card posts an anchored comment", %{
      conn: conn,
      scope: scope,
      goal: goal,
      task: task
    } do
      card = widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
      {:ok, view, _} = open(conn, scope)
      view |> element("#question-#{card.id}") |> render_click()
      view |> form("#composer-#{card.id}", body: "What counts as done?") |> render_submit()
      assert {:ok, [%{widget_id: id, body: "What counts as done?"}]} = Planning.take_wake(scope)
      assert id == card.id
    end
  end

  describe "exploring widgets" do
    test "the examples table highlights matching rows and says when none match", %{
      conn: conn,
      scope: scope,
      goal: goal,
      task: task
    } do
      widget = widget!(scope, goal, task, "examples", "examples")
      {:ok, view, _} = open(conn, scope)

      pick = fn sel ->
        view |> form("#examples-#{widget.id}", %{"sel" => sel}) |> render_change()
      end

      pick.(%{"0" => "free"})
      assert has_element?(view, "#row-#{widget.id}-r1[data-match=true]")
      assert has_element?(view, "#row-#{widget.id}-r2[data-match=true]")
      assert has_element?(view, "#row-#{widget.id}-r3[data-match=false]")

      pick.(%{"0" => "free", "1" => "2"})
      refute has_element?(view, "#row-#{widget.id}-r1[data-match=true]")
      assert has_element?(view, "#row-#{widget.id}-r2[data-match=true]")

      pick.(%{"0" => "pro", "1" => "1"})

      assert has_element?(
               view,
               "#examples-none-#{widget.id}",
               "No example covers this combination: Plan pro, Seats 1"
             )

      pick.(%{"0" => "", "1" => ""})
      refute has_element?(view, "#examples-none-#{widget.id}")
      refute has_element?(view, "#widget-#{widget.id} tr[data-match=true]")
    end

    test "the comparison re-ranks as the human re-weighs and keeps the human's weights", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      research = task!(scope, goal, %{"type" => "research", "title" => "Pick one"})
      widget = widget!(scope, goal, research, "findings", "comparison")
      {:ok, view, _} = open(conn, scope, 2)

      rank = fn ->
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#widget-#{widget.id} tbody tr")
        |> Enum.map(&(LazyHTML.attribute(&1, "id") |> hd()))
      end

      # Tied at 25 under the agent's weights, so the agent's order holds.
      assert rank.() == for(o <- ~w(mermaid flow react), do: "option-#{widget.id}-#{o}")

      view
      |> form("#weights-#{widget.id}", %{"w" => %{"fit" => "5", "setup" => "0", "power" => "5"}})
      |> render_change()

      assert rank.() == for(o <- ~w(flow mermaid react), do: "option-#{widget.id}-#{o}")

      assert {:ok, %{human: %{"weights" => %{"setup" => 0, "fit" => 5}}}} =
               Planning.fetch_widget(scope, widget.id)

      view |> element("#widget-#{widget.id} button", "Reset weights") |> render_click()
      assert rank.() == for(o <- ~w(mermaid flow react), do: "option-#{widget.id}-#{o}")
    end

    test "a quiz scores answers and a gate quiz is part of the lifecycle", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      learn = task!(scope, goal, %{"type" => "learn", "title" => "Learn"})
      {:ok, learn} = Planning.update_task(scope, learn, %{"force_step" => "check"})

      quiz =
        widget!(scope, goal, learn, "check", "quiz", %{
          "mode" => "gate",
          "gates" => "passed",
          "questions" => [
            %{
              "id" => "q1",
              "prompt" => "Pick b",
              "type" => "single",
              "options" => [
                %{"id" => "a", "text" => "A", "explanation" => "no"},
                %{"id" => "b", "text" => "B", "correct" => true, "explanation" => "yes"}
              ]
            }
          ]
        })

      {:ok, view, _} = open(conn, scope, 2)
      assert has_element?(view, "#transition-passed button[disabled]")
      assert has_element?(view, "#transition-passed", "q1 not answered correctly")

      view |> form("#answer-#{quiz.id}-q1", %{"answer" => "a"}) |> render_submit()
      assert has_element?(view, "#quiz-progress-#{quiz.id}", "1/1 answered · 0 correct")
      assert has_element?(view, "#transition-passed button[disabled]")

      view |> form("#answer-#{quiz.id}-q1", %{"answer" => "b"}) |> render_submit()
      assert has_element?(view, "#quiz-progress-#{quiz.id}", "1/1 answered · 1 correct")
      refute has_element?(view, "#transition-passed button[disabled]")
    end
  end

  test "the human releases a claim and comments", %{conn: conn, scope: scope, task: task} do
    {:ok, view, _html} = open(conn, scope)
    view |> element("#release-claim") |> render_click()
    assert {:ok, %{worktree_id: nil}} = Planning.fetch_task(scope, 1, 1)

    view |> form("#comment-form", comment: %{body: "Looks good"}) |> render_submit()
    assert has_element?(view, "#comments li[id^=comment-]", "Looks good")

    assert {:ok, [%{body: "Looks good", task_id: task_id}]} = Planning.take_inbox(scope)
    assert task_id == task.id
  end

  test "shows who hears the comments", %{conn: conn, scope: scope} do
    {:ok, view, _} = open(conn, scope)
    assert has_element?(view, "#task-listener", "is listening")
    Jarvis.Repo.update_all(Jarvis.Workspaces.AgentSession, set: [state: :ended])
    {:ok, view, _} = open(conn, scope)
    assert has_element?(view, "#task-listener", "No agent listening")
  end
end
