defmodule JarvisWeb.DesignSystemLiveTest do
  use JarvisWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Jarvis.Planning.Catalog

  test "shows every widget kind with an example", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/design-system")

    for kind <- Catalog.kinds() do
      assert has_element?(view, "#kind-#{kind}"), "missing #{kind}"
      assert has_element?(view, "#kind-#{kind} article[id^=widget-]"), "no widget for #{kind}"
    end
  end

  test "shows each widget's agent view", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/design-system")
    assert has_element?(view, "#kind-requirement details", "What the agent sees and writes")
  end

  test "requirements can be confirmed and a comment makes the simulated agent revise the card", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/design-system")
    id = "-1"

    view |> element("#confirm-#{id}") |> render_click()
    assert has_element?(view, "#widget-#{id}", "Confirmed")

    view |> element("#question-#{id}") |> render_click()
    view |> form("#composer-#{id}", body: "Make it measurable") |> render_submit()
    assert has_element?(view, "#thread-#{id}-widget", "Make it measurable")

    assert has_element?(
             view,
             "#thread-status-#{id}-widget",
             "Will be delivered at the session's next turn"
           )

    # The simulated agent (after its delay) answers, revises the card, and the confirmation is cleared.
    [asked | _] = :sys.get_state(view.pid).socket.assigns.comments
    send(view.pid, {:sandbox_agent, asked})

    assert has_element?(view, "#widget-#{id}", "within 2 seconds")
    refute has_element?(view, "#widget-#{id}", "Confirmed")
    assert has_element?(view, "#thread-#{id}-widget", "Widget updated")
    refute has_element?(view, "#thread-status-#{id}-widget")
  end

  test "the lifecycle demo moves a task when its condition holds", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/design-system")
    assert has_element?(view, "#transition-approve-requirements button[disabled]")

    for id <- [-1, -2, -3], do: view |> element("#confirm-#{id}") |> render_click()
    refute has_element?(view, "#transition-approve-requirements button[disabled]")

    view |> element("#transition-approve-requirements button") |> render_click()
    assert has_element?(view, "#step-design[data-state=current]")
    assert has_element?(view, "#step-requirements[data-state=previous]")

    view
    |> element("#transition-requirements-question button", "Act as the agent")
    |> render_click()

    assert has_element?(view, "#step-requirements[data-state=current]")
  end

  test "the Learn lifecycle is gated by the gate quiz", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/design-system")
    view |> element("#demo-type-learn") |> render_click()
    view |> element("#transition-explain button") |> render_click()
    view |> element("#transition-check-understanding button") |> render_click()
    assert has_element?(view, "#transition-passed button[disabled]")

    gate =
      Enum.find(
        :sys.get_state(view.pid).socket.assigns.widgets,
        &(&1.kind == "quiz" and &1.data["mode"] == "gate")
      )

    view |> form("#answer-#{gate.id}-g1", %{"answer" => ["a", "b", "c"]}) |> render_submit()
    refute has_element?(view, "#transition-passed button[disabled]")
  end

  test "the architecture tour steps forward and highlights its nodes", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/design-system")

    arch =
      Enum.find(:sys.get_state(view.pid).socket.assigns.widgets, &(&1.kind == "architecture"))

    view |> element("#tour-#{arch.id} button", "Start tour") |> render_click()
    assert has_element?(view, "#tour-#{arch.id}", "Step 1 of 2")
    assert has_element?(view, "#node-#{arch.id}-human.ring-4")
    assert has_element?(view, "#node-#{arch.id}-api.opacity-25")

    view |> element("#tour-#{arch.id} button", "Next") |> render_click()
    assert has_element?(view, "#tour-#{arch.id}", "Step 2 of 2")
    assert has_element?(view, "#node-#{arch.id}-human.opacity-25")

    view |> element("#node-#{arch.id}-db") |> render_click()
    assert has_element?(view, "#detail-#{arch.id}", "PostgreSQL")
  end

  test "claims light up their sources and findings can be marked", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/design-system")
    widgets = :sys.get_state(view.pid).socket.assigns.widgets
    sources = Enum.find(widgets, &(&1.kind == "sources"))
    findings = Enum.find(widgets, &(&1.kind == "findings"))

    view |> element("#claim-#{sources.id}-c1 button[phx-value-key=claim]") |> render_click()
    assert has_element?(view, "#source-#{sources.id}-mayer.bg-primary\\/10")
    refute has_element?(view, "#source-#{sources.id}-victor.bg-primary\\/10")
    assert has_element?(view, "#claim-#{sources.id}-c3", "Unsupported")

    view |> element("#mark-#{findings.id}-f1-agree") |> render_click()
    assert has_element?(view, "#mark-#{findings.id}-f1-agree[aria-pressed=true]")

    view |> element("#sev-#{findings.id}-nit") |> render_click()
    refute has_element?(view, "#finding-#{findings.id}-f1")
    assert has_element?(view, "#finding-#{findings.id}-f2")
  end
end
