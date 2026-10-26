defmodule Jarvis.CascadesTest do
  @moduledoc "A change upstream makes what builds on it out of date and removes approvals resting on it."
  use Jarvis.DataCase, async: false

  import Jarvis.Fixtures

  alias Jarvis.{Planning, Repo, Workspaces}
  alias Jarvis.Planning.Report

  setup do
    scope = agent_scope!(git_repo!())
    %{scope: scope, human: human_scope(scope), goal: goal!(scope)}
  end

  defp reason({:error, changeset}), do: errors_on(changeset).transition |> hd()
  defp stale(widget), do: Repo.reload(widget).human["stale"]

  defp quiz(questions) do
    %{
      "mode" => "feedback",
      "questions" =>
        for {id, explains} <- questions do
          %{
            "id" => id,
            "prompt" => "?",
            "type" => "single",
            "options" => [
              %{"id" => "a", "text" => "x", "correct" => true, "explanation" => "e"},
              %{"id" => "b", "text" => "y", "explanation" => "e"}
            ]
          }
          |> then(&if explains, do: Map.put(&1, "explains", explains), else: &1)
        end
    }
  end

  describe "a Feature" do
    setup %{scope: scope, human: human, goal: goal} do
      task = task!(scope, goal)
      r1 = widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
      r2 = widget!(scope, goal, task, "requirements", "requirement", requirement("R2"))
      {:ok, _} = Planning.widget_action(human, r1, "confirm", %{})

      evidence =
        widget!(scope, goal, task, "evidence", "evidence", %{
          "command" => "check",
          "result" => "passed",
          "requirements" =>
            for(id <- ~w(R1 R2), do: %{"requirement" => id, "test" => "t", "result" => "passed"})
        })

      review = widget!(scope, goal, task, "review", "findings", %{"findings" => []})
      %{task: task, r1: r1, r2: r2, evidence: evidence, review: review}
    end

    test "an unconfirmed requirement blocks approve design, implemented, and accept, by name", %{
      scope: scope,
      human: human,
      task: task
    } do
      assert reason(Planning.move_task(human, at_step!(task, "design"), "approve design")) =~
               "R2 not confirmed"

      assert reason(Planning.move_task(scope, at_step!(task, "implementation"), "implemented")) =~
               "R2 not confirmed"

      assert reason(Planning.move_task(human, at_step!(task, "acceptance"), "accept")) =~
               "R2 not confirmed"
    end

    test "a reworded requirement makes the evidence and the review out of date, and blocks", %{
      scope: scope,
      human: human,
      goal: goal,
      task: task,
      r1: r1,
      r2: r2,
      evidence: evidence,
      review: review
    } do
      {:ok, _} = Planning.widget_action(human, r2, "confirm", %{})
      task = at_step!(task, "design")
      scope = Workspaces.set_state(scope, :working)

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{"op" => "update", "id" => r1.id, "data" => requirement("R1", "do it better")}
        ])

      refute Repo.reload(r1).human["confirmed"]
      assert %{"because" => "R1 changed", "source" => source} = stale(evidence)
      assert source == r1.id
      assert stale(review)["because"] == "R1 changed"

      {:ok, _} = Planning.widget_action(human, Repo.reload(r1), "confirm", %{})
      assert reason(Planning.move_task(human, task, "approve design")) =~ "out of date"

      assert reason(Planning.move_task(human, at_step!(task, "acceptance"), "accept")) =~
               "produce it again"

      Workspaces.set_state(scope, :idle)
      {[report | _], _} = Planning.list_reports(goal, task)
      stale_ids = for %{"action" => "stale", "widget" => id} <- Report.items(report), do: id
      assert Enum.sort(stale_ids) == Enum.sort([evidence.id, review.id])
    end

    test "writing an out-of-date widget again clears its mark", %{
      scope: scope,
      goal: goal,
      task: task,
      r1: r1,
      review: review
    } do
      task = at_step!(task, "design")

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{"op" => "update", "id" => r1.id, "data" => requirement("R1", "again")},
          %{"op" => "update", "id" => review.id, "data" => %{"findings" => []}}
        ])

      assert stale(review) == nil
    end
  end

  test "a round with a new head makes the quiz and the findings out of date and blocks nothing",
       %{
         scope: scope,
         human: human,
         goal: goal
       } do
    task = at_step!(task!(scope, goal, %{"type" => "pr_review"}), "findings")
    quiz = widget!(scope, goal, task, "quiz", "quiz", quiz([{"q1", nil}]))

    findings =
      widget!(
        scope,
        goal,
        task,
        "findings",
        "findings",
        Jarvis.Planning.Catalog.example("findings")
      )

    round = fn head ->
      %{
        "op" => "add",
        "section" => "rounds",
        "kind" => "round",
        "data" => %{"number" => 2, "head" => head, "previous_head" => "aaa"}
      }
    end

    {:ok, _} = Planning.apply_widget_ops(scope, goal, task, [round.("aaa")])
    assert stale(quiz) == nil

    {:ok, _} = Planning.apply_widget_ops(scope, goal, task, [round.("bbb")])
    assert stale(quiz)["because"] =~ "new head bbb"
    assert stale(findings)["because"] =~ "new head bbb"

    assert {:ok, %{step: "done"}} = Planning.move_task(human, Repo.reload(task), "give verdict")
  end

  test "dig deeper makes the recommendation out of date and accept still works later", %{
    scope: scope,
    human: human,
    goal: goal
  } do
    task = at_step!(task!(scope, goal, %{"type" => "research"}), "findings")

    rec =
      widget!(
        scope,
        goal,
        task,
        "recommendation",
        "decision",
        Jarvis.Planning.Catalog.example("decision")
      )

    {:ok, task} = Planning.move_task(human, task, "dig deeper", %{"comment" => "check cost"})
    assert stale(rec)["because"] =~ "dig deeper"

    {:ok, task} = Planning.move_task(scope, task, "findings ready")
    assert {:ok, %{step: "done"}} = Planning.move_task(human, task, "accept")
  end

  test "a wrong answer to a linked Learn check question makes its explanation out of date", %{
    scope: scope,
    human: human,
    goal: goal
  } do
    task = at_step!(task!(scope, goal, %{"type" => "learn"}), "check")
    explained = widget!(scope, goal, task, "explanation", "prose", %{"text" => "How it works"})
    other = widget!(scope, goal, task, "explanation", "prose", %{"text" => "Elsewhere"})

    check =
      widget!(scope, goal, task, "check", "quiz", quiz([{"q1", "W#{explained.id}"}, {"q2", nil}]))

    {:ok, _} =
      Planning.widget_action(human, check, "answer", %{"question" => "q2", "answer" => "b"})

    assert stale(explained) == nil and stale(other) == nil

    {:ok, _} =
      Planning.widget_action(human, Repo.reload(check), "answer", %{
        "question" => "q1",
        "answer" => "b"
      })

    assert stale(explained)["because"] == "wrong answer to q1"
    assert stale(other) == nil

    assert {:ok, %{step: "explanation"}} =
             Planning.move_task(human, Repo.reload(task), "gaps found", %{"comment" => "q1"})
  end
end
