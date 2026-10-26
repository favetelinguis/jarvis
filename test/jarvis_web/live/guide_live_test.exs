defmodule JarvisWeb.GuideLiveTest do
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Jarvis.Planning.TaskType
  alias JarvisWeb.GuideLive

  defp open(conn) do
    {:ok, view, _} = live(conn, ~p"/guide")
    view
  end

  defp anchor(type), do: type |> GuideLive.path() |> String.split("#") |> List.last()
  defp dashed(name), do: String.replace(name, " ", "-")

  defp text(node), do: node |> LazyHTML.text() |> String.split() |> Enum.join(" ")

  defp nodes(view, selector),
    do: view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  describe "navigation" do
    test "every page shows a Guide link in the top navigation", %{conn: conn} do
      for path <- ["/", "/design-system", "/settings"] do
        {:ok, view, _} = live(conn, path)

        assert has_element?(
                 view,
                 ~s{#main-nav li:has(#nav-guide[href="/guide"]) + li:has(a[href="/design-system"]) + li:has(a[href="/settings"])}
               ),
               "no Guide link before Design system and Settings on #{path}"
      end
    end

    test "clicking Guide in the top navigation opens the Guide", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings")
      {:ok, guide, _} = view |> element("#nav-guide") |> render_click() |> follow_redirect(conn)
      assert has_element?(guide, "#concepts")
    end
  end

  test "the Guide is in English when the board language is Swedish", %{conn: conn} do
    {:ok, "sv"} = Jarvis.Language.save("sv")
    view = open(conn)
    assert has_element?(view, "#concepts h2", "Concepts")
    assert has_element?(view, "#other-workflows h2", "Other workflows")
  end

  describe "concepts" do
    test "Concepts explains each of the nine terms", %{conn: conn} do
      view = open(conn)

      for term <- ~w(goal task task-type step transition mover claim worktree session) do
        assert has_element?(view, "#concepts #concept-#{term}"), "no concept #{term}"
      end
    end

    test "a goal is a collection of tasks and the type decides steps and transitions", %{
      conn: conn
    } do
      view = open(conn)
      assert has_element?(view, "#concept-goal", "collection of tasks")
      assert has_element?(view, "#concept-task-type", "decides its steps and transitions")
    end
  end

  describe "claims and sessions" do
    test "a claim belongs to a worktree so worktrees work on different tasks at once", %{
      conn: conn
    } do
      view = open(conn)
      assert has_element?(view, "#claims", "A claim belongs to one worktree")
      assert has_element?(view, "#claims", "different tasks at the same time")
    end

    test "any session in the claiming worktree works on the task in any harness", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, "#claim-same-worktree", "Another harness, same worktree")
      assert has_element?(view, "#claim-same-worktree", "No release needed")
      assert has_element?(view, "#claim-same-worktree", "new session carries on")
    end

    test "Release claim on the task page releases a claim", %{conn: conn} do
      assert has_element?(open(conn), "#claims", "Release claim")
    end

    test "design claims the task for its worktree and replaces an earlier claim", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, "#claim-design", "Design")
      assert has_element?(view, "#claim-design", "replaces the old claim")
    end

    test "impl and impl-review work only on tasks their worktree claimed", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, "#claim-impl", "Implementation or Review")
      assert has_element?(view, "#claim-impl", "impl and impl-review work only on tasks")
    end

    test "Research, PR review, and Learn tasks are never claimed", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, "#claim-unclaimed", "Research, PR review, or Learn")
      assert has_element?(view, "#claim-unclaimed", "no claim to release")
    end
  end

  describe "comments" do
    test "a comment on a widget reaches the listening session at its next turn", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, "#comments", "listening session")
      assert has_element?(view, "#comments", "start of its next turn")
    end

    test "an idle session is never woken by a comment", %{conn: conn} do
      assert has_element?(open(conn), "#comments", "An idle session is never woken")
    end

    test "a comment waits, and the thread says so, when no session listens", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, "#comments", "the comment waits")
      assert has_element?(view, "#comments", "the thread says so")
    end
  end

  describe "lifecycles" do
    test "each type has a section with its lifecycle graph", %{conn: conn} do
      view = open(conn)

      for type <- TaskType.keys() do
        a = anchor(type)
        assert has_element?(view, "section##{a} h2", TaskType.label(type))

        for {key, label, _} <- TaskType.steps(type) do
          assert has_element?(view, "##{a} ##{a}-step-#{key}", label)
        end

        order = type |> TaskType.steps() |> Enum.map(&elem(&1, 0))
        index = &Enum.find_index(order, fn key -> key == &1 end)
        back = Enum.count(TaskType.transitions(type), &(index.(&1.to) < index.(&1.from)))
        assert Enum.count(nodes(view, "##{a} svg path[stroke-dasharray]")) == back

        for t <- TaskType.transitions(type) do
          assert has_element?(view, "##{a} svg text", t.name)
        end
      end
    end

    test "each type section has a card for every transition with its steps and mover", %{
      conn: conn
    } do
      view = open(conn)

      for type <- TaskType.keys(), t <- TaskType.transitions(type) do
        card = "##{anchor(type)}-transition-#{dashed(t.name)}"
        assert has_element?(view, card, t.name)
        assert has_element?(view, "#{card} [data-role=from]", TaskType.step_label(type, t.from))
        assert has_element?(view, "#{card} [data-role=to]", TaskType.step_label(type, t.to))
        assert has_element?(view, "#{card} [data-mover=#{t.mover}]")
      end
    end

    test "an agent's transition names the workflow that makes it", %{conn: conn} do
      view = open(conn)
      card = "#feature-transition-request-changes"
      assert has_element?(view, card, "impl-review")
      refute has_element?(view, card, "/impl-review")

      for type <- TaskType.keys(), %{mover: :agent} = t <- TaskType.transitions(type) do
        workflow = String.trim_leading(t.command, "/")

        assert has_element?(
                 view,
                 "##{anchor(type)}-transition-#{dashed(t.name)} [data-role=mover]",
                 "#{workflow} moves it"
               )
      end
    end

    test "a human's transition is a button on the task page", %{conn: conn} do
      view = open(conn)

      for type <- TaskType.keys(), %{mover: :human} = t <- TaskType.transitions(type) do
        assert has_element?(
                 view,
                 "##{anchor(type)}-transition-#{dashed(t.name)} [data-role=mover]",
                 "You click it on the task page"
               )
      end

      assert has_element?(view, "#feature-transition-approve-requirements", "task page")
      assert has_element?(view, "#research-transition-dig-deeper", "task page")
    end

    test "approve requirements shows its condition", %{conn: conn} do
      view = open(conn)

      assert has_element?(
               view,
               "#feature-transition-approve-requirements [data-role=condition]",
               "every requirement card is confirmed"
             )

      refute has_element?(view, "#research-transition-dig-deeper [data-role=condition]")
    end

    test "the Guide explains that a gate quiz blocks the transition it names", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, "#gates", "gate")
      assert has_element?(view, "#gates", "blocks the transition it names")
      assert has_element?(view, "#gates", "every question is answered correctly")
    end
  end

  describe "example flows" do
    test "each type has an example flow whose steps say what you type, the agent does, and you do",
         %{conn: conn} do
      view = open(conn)

      for type <- TaskType.keys() do
        a = anchor(type)
        items = nodes(view, "##{a}-flow > li")
        assert Enum.count(items) > 0, "#{TaskType.label(type)} has no example flow"

        for n <- 1..Enum.count(items) do
          for role <- ~w(say agent board) do
            assert has_element?(view, "##{a}-flow-#{n} [data-role=#{role}]"),
                   "#{TaskType.label(type)} flow step #{n} has no #{role}"
          end
        end
      end
    end

    test "every example flow follows the board's transitions from the first step to Done", %{
      conn: conn
    } do
      view = open(conn)

      for type <- TaskType.keys() do
        a = anchor(type)
        label = TaskType.label(type)

        moves = view |> nodes("##{a}-flow > li[data-move]") |> LazyHTML.attribute("data-move")

        movers =
          view
          |> nodes("##{a}-flow > li[data-move] [data-role=mover]")
          |> Enum.map(&text/1)

        assert length(movers) == length(moves), "#{label} flow: a move without its mover"

        last =
          moves
          |> Enum.zip(movers)
          |> Enum.reduce(TaskType.first_step(type), fn {name, mover}, step ->
            t =
              TaskType.find_transition(type, step, name) ||
                flunk(
                  "#{label} flow: no transition #{inspect(name)} out of #{TaskType.step_label(type, step)}"
                )

            who =
              if t.mover == :agent,
                do: "#{String.trim_leading(t.command, "/")} moves it",
                else: "You click #{t.name} on the task page"

            assert mover =~ who, "#{label} flow: #{inspect(name)} should say #{inspect(who)}"
            assert mover =~ TaskType.step_label(type, t.to)
            t.to
          end)

        assert TaskType.done?(last),
               "#{label} flow ends in #{TaskType.step_label(type, last)}, not Done"
      end
    end

    test "the Feature flow goes back with request changes and shows what follows", %{conn: conn} do
      moves =
        conn
        |> open()
        |> nodes("#feature-flow > li[data-move]")
        |> LazyHTML.attribute("data-move")

      assert "request changes" in moves
      after_back = Enum.drop_while(moves, &(&1 != "request changes"))
      assert "approve" in after_back
    end

    test "every prompt is a workflow name and its input, without harness syntax", %{conn: conn} do
      workflows = File.ls!("skills")
      prompts = conn |> open() |> nodes("[data-role=prompt]") |> Enum.map(&text/1)
      assert prompts != []

      for prompt <- prompts do
        refute String.starts_with?(prompt, ["/", "$"]), "harness syntax in #{inspect(prompt)}"
        [name | _] = String.split(prompt)
        assert name in workflows, "#{inspect(prompt)} does not start with a workflow name"
      end
    end

    test "the Feature section shows two tasks worked on at once in two worktrees", %{conn: conn} do
      view = open(conn)
      scenario = "#feature #scenario-parallel"
      assert has_element?(view, scenario, "worktree app: design Task 1.1")
      assert has_element?(view, scenario, "worktree app-search: design Task 1.2")
    end

    test "the Feature section shows a switch of harness in one worktree without a release", %{
      conn: conn
    } do
      view = open(conn)
      scenario = "#feature #scenario-harness-switch"
      assert has_element?(view, scenario, "In pi, in worktree app: design Task 1.1")
      assert has_element?(view, scenario, "In Codex, in the same worktree: impl Task 1.1")
      assert has_element?(view, scenario, "No release")
    end
  end

  describe "other workflows" do
    test "poc builds every task of a goal in one go", %{conn: conn} do
      assert has_element?(open(conn), "#workflow-poc", "Builds every task of a goal in one go")
    end

    test "poc moves tasks past the human's transitions", %{conn: conn} do
      assert has_element?(open(conn), "#workflow-poc", "past your transitions")
    end

    test "poc leaves a comment on every task it builds", %{conn: conn} do
      assert has_element?(open(conn), "#workflow-poc", "leaves a comment on every task")
    end

    test "poc marks the goal POC until the human clicks Mark reviewed", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, "#workflow-poc", "POC")
      assert has_element?(view, "#workflow-poc", "Mark reviewed")
    end

    test "eli5 re-explains the last answer in plain words and changes nothing", %{conn: conn} do
      view = open(conn)
      assert has_element?(view, "#workflow-eli5", "plain words")
      assert has_element?(view, "#workflow-eli5", "changes nothing")
    end
  end

  test "every DOM id on the page is unique", %{conn: conn} do
    ids = conn |> open() |> nodes("[id]") |> LazyHTML.attribute("id")
    assert ids -- Enum.uniq(ids) == []
  end
end
