defmodule JarvisWeb.DiataxisTest do
  @moduledoc "Lager 1: every page and section has one Diátaxis form, shown as a label."
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Jarvis.Fixtures

  alias Jarvis.Planning.TaskType
  alias JarvisWeb.Diataxis

  setup do
    scope = agent_scope!(git_repo!())
    goal = goal!(scope)
    for type <- ~w(feature research pr_review learn), do: task!(scope, goal, %{"type" => type})
    %{scope: scope}
  end

  test "every section of the goal and of every task type has exactly one form" do
    for type <- [:goal | TaskType.keys()],
        {key, _, _} <- TaskType.sections(type),
        do: assert(Diataxis.section(type, key) in [:tutorial, :how_to, :reference, :explanation])
  end

  test "every page shows its form as a label", %{conn: conn, scope: scope} do
    project = "/projects/#{scope.project.id}"

    pages = [
      {"/", :reference},
      {project, :reference},
      {"#{project}/goals/1", :reference},
      {"#{project}/goals/1/tasks/1", :reference},
      {"#{project}/goals/1/tasks/2", :explanation},
      {"#{project}/goals/1/tasks/3", :explanation},
      {"#{project}/goals/1/tasks/4", :tutorial},
      {"/guide", :explanation},
      {"/design-system", :reference},
      {"/settings", :how_to},
      {"/docs", :reference},
      {"/docs/tutorial", :tutorial}
    ]

    for {path, form} <- pages do
      {:ok, view, _} = live(conn, path)

      assert has_element?(view, "#page-form [data-form=#{form}]", Diataxis.label(form)),
             "#{path} does not show the form #{form}"
    end
  end

  test "every section on a task page shows its form", %{conn: conn, scope: scope} do
    path = "/projects/#{scope.project.id}/goals/1/tasks/4"

    for {key, _, _} <- TaskType.sections(:learn) do
      {:ok, view, _} = live(conn, "#{path}?section=#{key}")
      form = Diataxis.section(:learn, key)
      assert has_element?(view, "#section-#{key}-form[data-form=#{form}]")
    end
  end

  test "the docs start page lists the four forms, each with a purpose and a link", %{conn: conn} do
    {:ok, view, _} = live(conn, "/docs")

    for {form, label, purpose} <- Diataxis.all() do
      assert has_element?(view, "#doc-form-#{form} h2", label)
      assert has_element?(view, "#doc-form-#{form} p", purpose)
      assert has_element?(view, "#doc-form-#{form} a[href]")
    end

    assert has_element?(view, ~s(#doc-form-tutorial a[href="/docs/tutorial"]))
    assert has_element?(view, ~s(#doc-form-how_to a[href="/settings"]))
    assert has_element?(view, ~s(#doc-form-reference a[href="/design-system"]))
    assert has_element?(view, ~s(#doc-form-explanation a[href="/guide"]))
  end

  test "the tutorial says the outcome first, then the steps in order, then the check", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/docs/tutorial")

    ids =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("article > section")
      |> LazyHTML.attribute("id")

    assert ids == ~w(tutorial-outcome tutorial-steps tutorial-check)
    assert has_element?(view, "#tutorial-steps ol li")
  end

  test "settings is a how-to: numbered steps per job and a link to the explanation", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/settings")

    for id <- ~w(language-steps brand-steps integration-steps),
        do: assert(has_element?(view, "ol##{id} li"))

    assert has_element?(view, ~s(main a[href="/guide"]))
  end

  test "the widget catalog gives every kind the same fields in the same order", %{conn: conn} do
    {:ok, view, _} = live(conn, "/design-system")
    doc = view |> render() |> LazyHTML.from_fragment()
    lists = LazyHTML.query(doc, "[id$=-fields]")
    assert Enum.count(lists) > 10

    for list <- lists do
      terms = list |> LazyHTML.query("dt") |> Enum.map(&LazyHTML.text/1)
      assert terms == ["Kind", "Purpose", "Try this"]
    end
  end

  test "the board's own texts use sentences of at most 20 words", %{conn: conn} do
    for path <- ["/docs", "/docs/tutorial", "/settings", "/design-system", "/guide", "/"] do
      {:ok, view, _} = live(conn, path)

      long =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("main :is(p, li, h1, h2, button, label, dd):not([id^=widget-] *)")
        |> Enum.flat_map(fn node ->
          node |> LazyHTML.text() |> String.split(~r/(?<=[.!?:])\s+/, trim: true)
        end)
        |> Enum.filter(&(length(String.split(&1)) > 20))

      assert long == [], "sentences over 20 words on #{path}: #{inspect(long)}"
    end
  end
end
