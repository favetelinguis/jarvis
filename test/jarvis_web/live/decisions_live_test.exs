defmodule JarvisWeb.DecisionsLiveTest do
  @moduledoc "Turns, decisions, turn reports, evidence, and the human's view on the board's pages."
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Jarvis.Fixtures

  alias Jarvis.{Planning, Repo}
  alias Jarvis.Planning.TaskType

  setup do
    scope = agent_scope!(git_repo!())
    goal = goal!(scope)
    %{scope: scope, human: human_scope(scope), goal: goal}
  end

  defp open(conn, scope, task),
    do:
      live(
        conn,
        ~p"/projects/#{scope.project}/goals/#{Repo.preload(task, :goal).goal.number}/tasks/#{task.number}"
      )

  describe "sending work back on the task page" do
    test "the move is refused without a comment and asks for one", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      task = at_step!(task!(scope, goal), "acceptance")
      {:ok, view, _} = open(conn, scope, task)

      view |> element("#move-ask-request-changes") |> render_click()
      assert has_element?(view, "#move-comment-request-changes")

      view |> form("#move-form-request-changes", %{comment: ""}) |> render_submit()
      assert has_element?(view, "#move-error-request-changes", "Write a comment")
      assert Repo.reload(task).step == "acceptance"

      view |> form("#move-form-request-changes", %{comment: "R2 fails"}) |> render_submit()
      assert Repo.reload(task).step == "implementation"
      assert has_element?(view, "#comments [data-role=move]", "request changes")
      assert has_element?(view, "#comments", "R2 fails")
    end

    test "spec issue asks for the new task's title", %{conn: conn, scope: scope, goal: goal} do
      task = at_step!(task!(scope, goal), "acceptance")
      {:ok, view, _} = open(conn, scope, task)
      view |> element("#move-ask-spec-issue") |> render_click()
      assert has_element?(view, "#move-title-spec-issue")

      view
      |> form("#move-form-spec-issue", %{comment: "R1 is wrong", new_title: "Fix R1"})
      |> render_submit()

      assert {:ok, %{tasks: tasks}} = Planning.fetch_goal(scope, goal.number)
      assert Enum.any?(tasks, &(&1.title == "Fix R1" and &1.step == "requirements"))
    end
  end

  test "the Guide marks every transition that needs a comment, and who moves it", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/guide")

    for type <- TaskType.keys(), t <- TaskType.transitions(type) do
      card =
        "##{type |> Atom.to_string() |> String.replace("_", "-")}-transition-#{String.replace(t.name, " ", "-")}"

      assert has_element?(view, "#{card} [data-mover=#{t.mover}]")

      if t[:comment],
        do: assert(has_element?(view, "#{card} [data-role=comment]")),
        else: refute(has_element?(view, "#{card} [data-role=comment]"))
    end
  end

  describe "whose turn" do
    test "the task page says it is your turn and what each decision still lacks", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      task = task!(scope, goal)
      widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
      {:ok, _} = Planning.update_task(scope, task, %{"handoff" => true})
      {:ok, view, _} = open(conn, scope, task)

      assert has_element?(view, "#turn[data-turn=human]", "Your turn")

      assert has_element?(
               view,
               "#decision-approve-requirements [data-role=missing]",
               "R1 not confirmed"
             )
    end

    test "on the agent's turn it names the command, the worktree, and whether a session works", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      task = at_step!(task!(scope, goal), "implementation")
      {:ok, view, _} = open(conn, scope, task)
      assert has_element?(view, "#turn[data-turn=agent]", "Agent's turn")
      assert has_element?(view, "#turn-command", "/impl")
      assert has_element?(view, "#turn-command", "no worktree has claimed")
      assert has_element?(view, "#turn-session", "No session is working")

      {:ok, _} = Planning.update_task(scope, task, %{"claim" => true})
      Jarvis.Workspaces.set_state(scope, :working)
      {:ok, view, _} = open(conn, scope, task)
      assert has_element?(view, "#turn-command", scope.worktree.name)
      assert has_element?(view, "#turn-session", "is working on it now")
    end

    test "Done is nobody's turn", %{conn: conn, scope: scope, goal: goal} do
      task = at_step!(task!(scope, goal), "done")
      {:ok, view, _} = open(conn, scope, task)
      assert has_element?(view, "#turn[data-turn=none]", "Nobody's turn")
    end

    test "Skip quiz on the task page gives the turn to the agent", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      task = at_step!(task!(scope, goal, %{"type" => "pr_review"}), "quiz")
      {:ok, view, _} = open(conn, scope, task)
      view |> element("#skip-quiz") |> render_click()
      assert has_element?(view, "#turn[data-turn=agent]")
      refute has_element?(view, "#skip-quiz")
    end

    test "the project board shows each task's turn and filters to yours", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      mine = at_step!(task!(scope, goal, %{"title" => "Mine"}), "acceptance")
      theirs = task!(scope, goal, %{"title" => "Theirs"})
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}")

      assert has_element?(view, "#turn-#{mine.id}[data-turn=human]", "Your turn")
      assert has_element?(view, "#turn-#{theirs.id}[data-turn=agent]", "Agent's turn")

      view |> element("#filter-mine") |> render_click()
      assert has_element?(view, "#filter-mine[aria-pressed=true]")
      assert has_element?(view, "#task-#{mine.id}")
      refute has_element?(view, "#task-#{theirs.id}")
    end

    test "the Guide explains turns and handoffs and gives each step's turn", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/guide")
      assert has_element?(view, "#concept-turn")
      assert has_element?(view, "#concept-handoff", "without leaving it")
      assert has_element?(view, "#turns", "hands the step over")

      for type <- TaskType.keys(), {key, _, _} <- TaskType.steps(type) do
        a = type |> Atom.to_string() |> String.replace("_", "-")
        assert has_element?(view, "##{a}-steps-#{key} [data-role=turn]")
      end

      assert has_element?(view, "#feature-steps-acceptance [data-role=turn]", "Yours")
      assert has_element?(view, "#feature-steps-design [data-role=turn]", "hands the step over")
    end
  end

  describe "turn reports" do
    setup %{scope: scope, goal: goal} do
      task = task!(scope, goal)
      widget = widget!(scope, goal, task, "intent", "prose", %{"text" => "before"})
      scope = Jarvis.Workspaces.set_state(scope, :working)
      %{scope: scope, task: task, widget: widget}
    end

    defp agent_turn(scope, goal, task, ops, meta) do
      {:ok, _} = Planning.apply_widget_ops(scope, goal, task, ops, meta)
      Jarvis.Workspaces.set_state(scope, :idle)
      Jarvis.Workspaces.set_state(scope, :working)
    end

    test "an unread report sits on top with before and after, the reason, and what is needed", %{
      conn: conn,
      scope: scope,
      goal: goal,
      task: task,
      widget: widget
    } do
      agent_turn(
        scope,
        goal,
        task,
        [%{"op" => "update", "id" => widget.id, "data" => %{"text" => "after"}}],
        %{
          "reason" => "Q3 → intent sharpened",
          "needs" => "confirm R1"
        }
      )

      {:ok, view, _} = open(conn, scope, task)
      [report] = elem(Planning.list_reports(goal, task), 0)
      entry = "#report-#{report.id}-entry-0"

      assert has_element?(view, "#report-#{report.id}[data-read=false]")

      assert has_element?(
               view,
               "#report-#{report.id} details:not([open]) > summary",
               "Turn report"
             )

      assert has_element?(
               view,
               "#report-#{report.id} details #{entry} [data-role=before]",
               "before"
             )

      assert has_element?(view, "#{entry} [data-role=after]", "after")
      assert has_element?(view, "#{entry} [data-role=reason]", "Q3 → intent sharpened")
      assert has_element?(view, "#report-#{report.id}-needs", "confirm R1")
      assert has_element?(view, "#widget-#{widget.id}[data-changed=true]")

      view |> element("#read-report-#{report.id}") |> render_click()
      assert has_element?(view, "#turn-history #report-#{report.id}[data-read=true]")
      assert has_element?(view, "#widget-#{widget.id}[data-changed=false]")
    end

    test "a change without a reason says so", %{conn: conn, scope: scope, goal: goal, task: task} do
      agent_turn(
        scope,
        goal,
        task,
        [%{"op" => "add", "section" => "intent", "kind" => "prose", "data" => %{"text" => "x"}}],
        %{}
      )

      {:ok, view, _} = open(conn, scope, task)
      assert has_element?(view, "#turn-reports [data-role=reason]", "No reason given")
    end

    test "read reports are kept newest first", %{
      conn: conn,
      scope: scope,
      goal: goal,
      task: task,
      human: human
    } do
      for text <- ~w(one two) do
        agent_turn(
          scope,
          goal,
          task,
          [
            %{
              "op" => "add",
              "section" => "intent",
              "kind" => "prose",
              "data" => %{"text" => text}
            }
          ],
          %{}
        )
      end

      {unread, _} = Planning.list_reports(goal, task)
      for r <- unread, do: Planning.read_report(human, r.id)
      {:ok, view, _} = open(conn, scope, task)

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#turn-history article")
        |> LazyHTML.attribute("id")

      assert ids == Enum.map(unread, &"report-#{&1.id}")
      assert [a, b] = Enum.map(unread, & &1.id)
      assert a > b
    end

    test "the goal page shows reports of the goal's changes", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      {:ok, _} = Planning.create_task(scope, goal, %{"title" => "Split off"})
      Jarvis.Workspaces.set_state(scope, :idle)
      {:ok, view, _} = live(conn, ~p"/projects/#{scope.project}/goals/#{goal.number}")

      assert has_element?(
               view,
               "#turn-reports article details:not([open]) > summary",
               "Turn report"
             )

      assert has_element?(view, "#turn-reports details [data-action=task_created]", "Split off")
    end

    test "the Guide explains turn reports", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/guide")
      assert has_element?(view, "#concept-turn-report")
      assert has_element?(view, "#turn-reports", "Mark turn as read")
    end
  end

  describe "evidence at your gate" do
    test "Design shows the review report; Acceptance shows the evidence and the review", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      task = at_step!(task!(scope, goal), "design")
      {:ok, view, _} = open(conn, scope, task)
      assert has_element?(view, "#turn-review", "No review report yet")

      widget!(
        scope,
        goal,
        task,
        "review",
        "findings",
        Jarvis.Planning.Catalog.example("findings")
      )

      {:ok, view, _} = open(conn, scope, task)
      assert has_element?(view, "#turn-review", "2 finding(s)")
      refute has_element?(view, "#turn-proof")

      widget!(scope, goal, task, "requirements", "requirement", requirement("R3"))

      widget!(
        scope,
        goal,
        task,
        "evidence",
        "evidence",
        Jarvis.Planning.Catalog.example("evidence")
      )

      at_step!(task, "acceptance")
      {:ok, view, _} = open(conn, scope, task)
      assert has_element?(view, "#turn-proof", "Check passed")
      assert has_element?(view, "#turn-proof", "1 of 1 tests passed")
      assert has_element?(view, "#turn-review", "2 finding(s)")
    end

    test "the Guide says which evidence each handoff needs", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/guide")
      assert has_element?(view, "#evidence-design", "review report")
      assert has_element?(view, "#evidence-impl", "every requirement has a")
    end
  end

  describe "out of date" do
    test "a widget shows Out of date with what changed upstream and a link to it", %{
      conn: conn,
      scope: scope,
      goal: goal
    } do
      task = at_step!(task!(scope, goal), "design")
      r1 = widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
      review = widget!(scope, goal, task, "review", "findings", %{"findings" => []})

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{"op" => "update", "id" => r1.id, "data" => requirement("R1", "changed")}
        ])

      {:ok, view, _} =
        live(
          conn,
          ~p"/projects/#{scope.project}/goals/#{goal.number}/tasks/#{task.number}?section=review"
        )

      assert has_element?(view, "#stale-#{review.id}", "Out of date")
      assert has_element?(view, "#stale-#{review.id}", "R1 changed")

      assert has_element?(
               view,
               ~s(#stale-#{review.id} a[href="?section=requirements#widget-#{r1.id}"])
             )
    end

    test "the Guide says what becomes out of date from what, and what it blocks", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/guide")
      assert has_element?(view, "#cascade-requirement", "approve design, implemented, accept")
      assert has_element?(view, "#cascade-head", "Nothing")
      assert has_element?(view, "#cascade-dig", "recommendation")
      assert has_element?(view, "#cascade-check", "explanation widget")
    end
  end

  test "the Guide lists the sections each step owns and limits force_step to POC goals", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/guide")
    assert has_element?(view, "#section-owners", "only in a goal marked POC")
    assert has_element?(view, "#feature-steps-acceptance [data-role=owns]", "Nothing")
    assert has_element?(view, "#feature-steps-implementation [data-role=owns]", "Evidence")
    assert has_element?(view, "#pr-review-steps-findings [data-role=owns]", "Your view")
  end

  describe "your view in a PR review" do
    setup %{scope: scope, goal: goal} do
      task = at_step!(task!(scope, goal, %{"type" => "pr_review"}), "findings")

      findings =
        widget!(
          scope,
          goal,
          task,
          "findings",
          "findings",
          Jarvis.Planning.Catalog.example("findings")
        )

      later =
        widget!(scope, goal, task, "rounds", "findings", %{
          "findings" => [
            %{"id" => "r2-f1", "severity" => "minor", "path" => "a.ex", "explanation" => "later"}
          ]
        })

      %{task: task, findings: findings, later: later}
    end

    defp findings_page(conn, scope, task, section \\ "findings"),
      do:
        live(
          conn,
          ~p"/projects/#{scope.project}/goals/#{Repo.preload(task, :goal).goal.number}/tasks/#{task.number}?section=#{section}"
        )

    test "the first round's findings stay hidden until you save your view", %{
      conn: conn,
      scope: scope,
      task: task,
      findings: findings,
      later: later
    } do
      {:ok, view, _} = findings_page(conn, scope, task)
      assert has_element?(view, "#picture-form")
      refute has_element?(view, "#widget-#{findings.id}")

      {:ok, rounds, _} = findings_page(conn, scope, task, "rounds")
      assert has_element?(rounds, "#widget-#{later.id}")

      view |> form("#picture-form", %{picture: ""}) |> render_submit()
      assert has_element?(view, "#picture-error", "at least one concern")
      refute has_element?(view, "#widget-#{findings.id}")

      view
      |> form("#picture-form", %{picture: "timeout missing\nmigration cannot be undone"})
      |> render_submit()

      assert has_element?(view, "#widget-#{findings.id}")
      assert has_element?(view, "#concern-c1", "timeout missing")
    end

    test "skipping shows the findings", %{
      conn: conn,
      scope: scope,
      task: task,
      findings: findings
    } do
      {:ok, view, _} = findings_page(conn, scope, task)
      view |> element("#skip-picture") |> render_click()
      assert has_element?(view, "#widget-#{findings.id}")
    end

    test "matches label each finding and each concern no finding covers", %{
      conn: conn,
      scope: scope,
      human: human,
      goal: goal,
      task: task,
      findings: findings
    } do
      {:ok, task} =
        Planning.save_picture(human, task, "timeout missing\nmigration cannot be undone")

      widget!(
        scope,
        goal,
        task,
        "picture",
        "view_matches",
        Jarvis.Planning.Catalog.example("view_matches")
      )

      {:ok, view, _} = findings_page(conn, scope, task)

      assert has_element?(
               view,
               "#match-badge-#{findings.id}-f1[data-match=both]",
               "You saw this too"
             )

      assert has_element?(
               view,
               "#match-badge-#{findings.id}-f2[data-match=agent]",
               "Only the agent"
             )

      assert has_element?(view, "#concern-badge-c2", "Only you")
      refute has_element?(view, "#concern-badge-c1")
    end

    test "a turn report hides the first round's findings until you save your view", %{
      conn: conn,
      scope: scope,
      human: human,
      goal: goal
    } do
      task = at_step!(task!(scope, goal, %{"type" => "pr_review"}), "quiz")
      scope = Jarvis.Workspaces.set_state(scope, :working)

      {:ok, _} =
        Planning.apply_widget_ops(
          scope,
          goal,
          task,
          [
            %{
              "op" => "add",
              "section" => "findings",
              "kind" => "findings",
              "data" => Jarvis.Planning.Catalog.example("findings")
            }
          ],
          %{"reason" => "found the missing gate check"}
        )

      Jarvis.Workspaces.set_state(scope, :idle)
      task = at_step!(task, "findings")
      {:ok, view, _} = findings_page(conn, scope, task)

      assert has_element?(view, "#turn-reports [data-role=hidden]", "your view")
      refute has_element?(view, "#turn-reports", "gate quiz")
      refute has_element?(view, "#turn-reports", "missing gate check")

      {:ok, _} = Planning.save_picture(human, task, "a concern")
      {:ok, view, _} = findings_page(conn, scope, task)
      refute has_element?(view, "#turn-reports [data-role=hidden]")
      assert has_element?(view, "#turn-reports", "gate quiz")
    end

    test "the Guide explains your view and why the findings wait", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/guide")
      assert has_element?(view, "#your-view", "stay hidden until then")
      assert has_element?(view, "#your-view", "Only you")
    end
  end
end
