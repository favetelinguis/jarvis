defmodule JarvisWeb.MayerTest do
  @moduledoc "Lager 3: explanations next to what they explain, one step at a time, nothing extra."
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Jarvis.Fixtures

  alias Jarvis.Planning.Catalog

  setup do
    scope = agent_scope!(git_repo!())
    goal = goal!(scope)
    task = task!(scope, goal, %{"title" => "Show it"})
    %{scope: scope, goal: goal, task: task}
  end

  defp open(conn, scope, query \\ ""),
    do: live(conn, ~p"/projects/#{scope.project}/goals/1/tasks/1" <> query)

  defp walk_step(i),
    do: %{
      "id" => "s#{i}",
      "path" => "lib/a#{i}.ex",
      "code" => "x = #{i}",
      "narration" => "Step #{i}."
    }

  test "a part's explanation sits on the part, inside the architecture widget", %{
    conn: conn,
    scope: scope,
    goal: goal,
    task: task
  } do
    arch = widget!(scope, goal, task, "sketch", "architecture")
    {:ok, view, _} = open(conn, scope)
    view |> element("#node-#{arch.id}-human") |> render_click()

    assert has_element?(
             view,
             "#arch-#{arch.id} [data-pz-stage] #detail-#{arch.id}",
             "Watches the board"
           )

    refute has_element?(view, "#node-#{arch.id}-human [class*=hero-]")
  end

  test "a walkthrough shows one step at a time with Step n of m", %{
    conn: conn,
    scope: scope,
    goal: goal,
    task: task
  } do
    three =
      widget!(scope, goal, task, "sketch", "walkthrough", %{
        "steps" => Enum.map(1..3, &walk_step/1)
      })

    one = widget!(scope, goal, task, "sketch", "walkthrough", %{"steps" => [walk_step(1)]})
    {:ok, view, _} = open(conn, scope)

    assert has_element?(view, "#walk-counter-#{three.id}", "Step 1 of 3")
    assert has_element?(view, "#walk-next-#{three.id}")
    refute has_element?(view, "#walk-prev-#{three.id}")

    view |> element("#walk-next-#{three.id}") |> render_click()
    assert has_element?(view, "#walk-counter-#{three.id}", "Step 2 of 3")
    assert has_element?(view, "#walk-prev-#{three.id}")

    refute has_element?(view, "#walk-counter-#{one.id}")
    refute has_element?(view, "#walk-next-#{one.id}")
    refute has_element?(view, "#walk-prev-#{one.id}")
  end

  test "a quiz shows one question at a time", %{conn: conn, scope: scope, goal: goal, task: task} do
    [q | _] = Catalog.example("quiz")["questions"]
    questions = for i <- 1..5, do: %{q | "id" => "q#{i}"}

    quiz =
      widget!(scope, goal, task, "tests", "quiz", %{
        "mode" => "self_study",
        "questions" => questions
      })

    {:ok, view, _} = open(conn, scope, "?section=tests")

    assert has_element?(view, "#quiz-step-#{quiz.id}", "Step 1 of 5")
    assert has_element?(view, "#question-#{quiz.id}-q1")
    refute has_element?(view, "#question-#{quiz.id}-q2")
    refute has_element?(view, "#quiz-prev-#{quiz.id}")

    view |> element("#quiz-next-#{quiz.id}") |> render_click()
    assert has_element?(view, "#quiz-step-#{quiz.id}", "Step 2 of 5")
    assert has_element?(view, "#question-#{quiz.id}-q2")
    refute has_element?(view, "#question-#{quiz.id}-q1")
  end

  test "a glossary term in widget text shows its meaning in place, but not inside code", %{
    conn: conn,
    scope: scope,
    goal: goal,
    task: task
  } do
    widget!(scope, goal, nil, "glossary", "glossary_term", %{
      "term" => "Tavlan",
      "meaning" => "Jarvis webbgränssnitt."
    })

    prose =
      widget!(scope, goal, task, "intent", "prose", %{"text" => "`tavlan` and then tavlan again."})

    {:ok, view, _} = open(conn, scope, "?section=intent")

    assert has_element?(view, "#widget-#{prose.id} button.term[data-term]", "tavlan")
    assert has_element?(view, "#widget-#{prose.id} .term-def[hidden]", "Jarvis webbgränssnitt.")
    refute has_element?(view, "#widget-#{prose.id} code button.term")
  end

  defp terms_in(text, terms, language) do
    glossary =
      JarvisWeb.WidgetComponents.glossary(
        for(t <- terms, do: %{kind: "glossary_term", data: %{"term" => t, "meaning" => "M"}}),
        language
      )

    (&JarvisWeb.PlanningComponents.markdown/1)
    |> render_component(text: text, glossary: glossary)
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("button.term")
    |> Enum.map(&LazyHTML.text/1)
  end

  test "a glossary term matches its Swedish inflected forms, not other words" do
    for {text, found} <- [
          {"Tavlan visar allt.", ["Tavlan"]},
          {"Alla tavlor.", ["tavlor"]},
          {"Tavlornas ram.", ["Tavlornas"]},
          {"En tavlas ram.", ["tavlas"]},
          {"En stavla och tavlamålning.", []},
          {"Uppgifterna och uppgiftens.", ["Uppgifterna"]},
          {"Pojkarna och pojken.", ["Pojkarna"]},
          {"Flyttarna.", ["Flyttarna"]},
          {"Målet.", ["Målet"]},
          {"Agent sessionerna.", ["Agent sessionerna"]}
        ] do
      assert terms_in(
               text,
               ["tavla", "uppgift", "pojke", "flyttare", "mål", "agent session"],
               "sv"
             ) ==
               found,
             text
    end
  end

  test "in English a glossary term matches plurals and possessives only" do
    assert terms_in("Two boards.", ["board"], "en") == ["boards"]
    assert terms_in("The board's owner.", ["board"], "en") == ["board's"]
    assert terms_in("The boarden.", ["board"], "en") == []
  end

  test "the task shows a table of contents with counts and forms, and one section at a time", %{
    conn: conn,
    scope: scope,
    goal: goal,
    task: task
  } do
    widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
    widget!(scope, goal, task, "requirements", "requirement", requirement("R2"))
    widget!(scope, goal, task, "sketch", "prose", %{"text" => "A sketch"})
    {:ok, view, _} = open(conn, scope)

    assert has_element?(view, "#toc-requirements", "2 widgets")
    assert has_element?(view, "#toc-requirements [data-form=reference]")
    assert has_element?(view, "#toc-sketch", "1 widget")
    assert has_element?(view, "#toc-sketch [data-form=explanation]")
    assert has_element?(view, "#toc-requirements[aria-current]")
    assert has_element?(view, "#section-requirements")
    refute has_element?(view, "#section-sketch")

    view |> element("#toc-sketch") |> render_click()
    assert has_element?(view, "#section-sketch")
    refute has_element?(view, "#section-requirements")
  end

  test "a diagram that cannot be drawn shows its source and the error", %{
    conn: conn,
    scope: scope,
    goal: goal,
    task: task
  } do
    diagram = widget!(scope, goal, task, "sketch", "diagram", %{"source" => "graph TD; A-->"})
    {:ok, view, _} = open(conn, scope)

    view
    |> element("[phx-hook=Mermaid][data-widget='#{diagram.id}']")
    |> render_hook("widget:render_error", %{"widget" => diagram.id, "message" => "Parse error"})

    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#diagram-error-#{diagram.id}", "Parse error")
    assert has_element?(view, "#diagram-error-#{diagram.id} pre", "graph TD; A-->")
  end

  test "a callout names its tone in a word", %{conn: conn, scope: scope, goal: goal, task: task} do
    callout =
      widget!(scope, goal, task, "intent", "callout", %{"tone" => "risk", "title" => "Big"})

    {:ok, view, _} = open(conn, scope)
    assert has_element?(view, "#widget-#{callout.id}", "Risk")
  end
end
