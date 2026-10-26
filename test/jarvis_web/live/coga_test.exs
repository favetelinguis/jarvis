defmodule JarvisWeb.CogaTest do
  @moduledoc "Lager 2: orientation, confirmation, memory support, and calm live updates."
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Jarvis.Fixtures

  alias Jarvis.Planning

  setup do
    scope = agent_scope!(git_repo!())
    goal = goal!(scope)
    task = task!(scope, goal, %{"title" => "Show it"})
    %{scope: scope, goal: goal, task: task}
  end

  defp open(conn, scope), do: live(conn, ~p"/projects/#{scope.project}/goals/1/tasks/1")

  test "the task page says where the human is and what can happen next", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = open(conn, scope)
    assert has_element?(view, "#breadcrumbs a[aria-current=page]", "Task 1.1 (Requirements)")
    assert has_element?(view, "#where-next", "You are in step Requirements")
    assert has_element?(view, "#where-next", "approve requirements")
    assert has_element?(view, "#where-next", "(you, blocked)")
  end

  test "a move is made only after the human confirms it, and can be called off", %{
    conn: conn,
    scope: scope,
    goal: goal,
    task: task
  } do
    card = widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
    {:ok, view, _} = open(conn, scope)
    view |> element("#confirm-#{card.id}") |> render_click()
    view |> element("#move-ask-approve-requirements") |> render_click()
    assert has_element?(view, "#move-confirmation-approve-requirements", "Next:")
    view |> element("#move-cancel-approve-requirements") |> render_click()
    refute has_element?(view, "#move-confirmation-approve-requirements")
    assert {:ok, %{step: "requirements"}} = Planning.fetch_task(scope, 1, 1)
  end

  test "every button names its action in text", %{
    conn: conn,
    scope: scope,
    goal: goal,
    task: task
  } do
    widget!(scope, goal, task, "sketch", "architecture")

    for path <- ["/design-system", "/projects/#{scope.project.id}/goals/1/tasks/1"] do
      {:ok, view, _} = live(conn, path)

      unnamed =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("button")
        |> Enum.filter(&(String.trim(LazyHTML.text(&1)) == ""))
        |> Enum.map(&LazyHTML.to_html/1)

      assert unnamed == [], "buttons without a text label on #{path}: #{inspect(unnamed)}"
    end
  end

  test "an agent's change to a widget is marked until the human reads it; the human's own action is not",
       %{conn: conn, scope: scope, goal: goal, task: task} do
    widget = widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
    other = widget!(scope, goal, task, "requirements", "requirement", requirement("R2"))
    {:ok, view, _} = open(conn, scope)
    refute has_element?(view, "[data-changed=true]")

    view |> element("#confirm-#{other.id}") |> render_click()
    refute has_element?(view, "#changed-#{other.id}")

    {:ok, _} =
      Planning.apply_widget_ops(scope, goal, task, [
        %{"op" => "update", "id" => widget.id, "data" => requirement("R1", "do it faster")}
      ])

    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#changed-#{widget.id}", "Updated by an agent")
    refute has_element?(view, "#changed-#{other.id}")

    view |> element("#changed-#{widget.id} button", "Mark as read") |> render_click()
    refute has_element?(view, "#changed-#{widget.id}")
  end

  test "unsent comments and quiz answers are kept as drafts in the browser", %{
    conn: conn,
    scope: scope,
    goal: goal,
    task: task
  } do
    quiz = widget!(scope, goal, task, "tests", "quiz")
    {:ok, view, _} = open(conn, scope)
    assert has_element?(view, "#comment-form[phx-hook=Draft]")
    assert has_element?(view, "form[id^=answer-#{quiz.id}-][phx-hook=Draft]")
  end

  # The element a control sends focus to on the client (its JS.focus target),
  # asserted to exist and to take focus.
  defp focus_lands(view, selector, attr \\ "phx-click") do
    [command] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attr)

    to = Enum.find_value(Jason.decode!(command), fn [op, args] -> op == "focus" && args["to"] end)
    assert to, "#{selector} sends no focus"
    assert has_element?(view, "#{to}[tabindex='-1']") or has_element?(view, "button#{to}"), to
    to
  end

  test "a control that closes or replaces itself sends focus to a place that stays", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/design-system")
    widgets = :sys.get_state(view.pid).socket.assigns.widgets
    arch = Enum.find(widgets, &(&1.kind == "architecture"))
    walk = Enum.find(widgets, &(&1.kind == "walkthrough" and length(&1.data["steps"]) > 1))
    quiz = Enum.find(widgets, &(&1.kind == "quiz" and length(&1.data["questions"]) > 1))

    assert focus_lands(view, "#tour-start-#{arch.id}") == "#tour-#{arch.id}"
    view |> element("#tour-start-#{arch.id}") |> render_click()
    assert focus_lands(view, "#tour-next-#{arch.id}") == "#tour-#{arch.id}"
    view |> element("#tour-next-#{arch.id}") |> render_click()
    assert focus_lands(view, "#tour-prev-#{arch.id}") == "#tour-#{arch.id}"
    assert focus_lands(view, "#tour-end-#{arch.id}") == "#tour-#{arch.id}"

    assert focus_lands(view, "#walk-next-#{walk.id}") == "#walk-counter-#{walk.id}"
    view |> element("#walk-next-#{walk.id}") |> render_click()
    assert focus_lands(view, "#walk-prev-#{walk.id}") == "#walk-counter-#{walk.id}"

    assert focus_lands(view, "#quiz-next-#{quiz.id}") == "#quiz-step-#{quiz.id}"

    view
    |> element("#widget--1 header button[aria-label='Comment on this widget']")
    |> render_click()

    opener = focus_lands(view, "#composer--1 button[type=button]")
    assert has_element?(view, "#widget--1 header button#{opener}")
    assert focus_lands(view, "#composer--1", "phx-submit") == opener

    for id <- [-1, -2, -3], do: view |> element("#confirm-#{id}") |> render_click()
    view |> element("#move-ask-approve-requirements") |> render_click()

    assert focus_lands(view, "#move-cancel-approve-requirements") ==
             "#transition-approve-requirements"

    assert focus_lands(view, "#move-confirm-approve-requirements") == "#lifecycle"
  end

  test "the comment field has a visible label, says it is required, and its error says how to fix it",
       %{conn: conn, scope: scope} do
    {:ok, view, _} = open(conn, scope)
    assert has_element?(view, "#comment-form label[for=comment_body]", "(required)")

    view |> form("#comment-form", comment: %{body: "   "}) |> render_submit()

    assert has_element?(
             view,
             "#comment_body[aria-invalid=true][aria-describedby=comment_body-error]"
           )

    assert has_element?(view, "#comment_body-error", "The comment is empty")
    assert has_element?(view, "#comment_body-error", "Write")
  end

  test "messages stay until the human closes them", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings")

    view
    |> form("#brand-form", %{"colors" => Jarvis.Theme.defaults()})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Brand colors saved.")
    assert has_element?(view, "#flash-info button", "Close")
    refute view |> element("#flash-info") |> render() =~ "phx-mounted"
  end
end
