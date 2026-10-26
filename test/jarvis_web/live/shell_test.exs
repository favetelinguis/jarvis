defmodule JarvisWeb.ShellTest do
  @moduledoc "Every page is drawn by the one shell (see .agents/skills/jarvis-design)."
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Jarvis.Fixtures

  @nav ~w(nav-projects nav-docs nav-guide nav-design-system nav-settings)

  setup do
    scope = agent_scope!(git_repo!())
    goal = goal!(scope)
    for type <- ~w(feature research pr_review learn), do: task!(scope, goal, %{"type" => type})
    %{scope: scope}
  end

  defp pages(scope) do
    project = "/projects/#{scope.project.id}"

    ["/", project, "#{project}/goals/1", "/guide", "/design-system", "/settings"] ++
      for n <- 1..4, do: "#{project}/goals/1/tasks/#{n}"
  end

  test "every page has a skip link, the main navigation in one order, a main landmark, and one h1",
       %{conn: conn, scope: scope} do
    for path <- pages(scope) do
      {:ok, view, _} = live(conn, path)
      doc = view |> render() |> LazyHTML.from_fragment()

      assert has_element?(view, ~s(a#skip-link[href="#main"])), "no skip link on #{path}"
      assert has_element?(view, ~s(main#main)), "no main landmark on #{path}"

      ids = doc |> LazyHTML.query("nav#main-nav a") |> LazyHTML.attribute("id")
      assert ids == @nav, "main navigation differs on #{path}: #{inspect(ids)}"

      assert doc |> LazyHTML.query("h1") |> Enum.count() == 1, "not exactly one h1 on #{path}"
    end
  end

  test "the breadcrumbs mark the current page", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, "/projects/#{scope.project.id}/goals/1/tasks/2")
    assert has_element?(view, ~s(#breadcrumbs a[aria-current=page]), "Task 1.2")
  end

  test "every page applies the reader's display settings before the first paint", %{conn: conn} do
    html = conn |> get("/") |> html_response(200)
    [head, _] = String.split(html, "</head>", parts: 2)
    assert head =~ "window.jarvisDisplay" or head =~ "global.jarvisDisplay"
  end
end
