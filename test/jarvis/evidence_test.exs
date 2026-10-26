defmodule Jarvis.EvidenceTest do
  @moduledoc "An agent hands a Feature over only with evidence the human can check."
  use Jarvis.DataCase, async: false

  import Jarvis.Fixtures

  alias Jarvis.Planning

  setup do
    scope = agent_scope!(git_repo!())
    human = human_scope(scope)
    goal = goal!(scope)
    task = task!(scope, goal)

    for id <- ~w(R1 R2 R3) do
      w = widget!(scope, goal, task, "requirements", "requirement", requirement(id))
      {:ok, _} = Planning.widget_action(human, w, "confirm", %{})
    end

    %{scope: scope, human: human, goal: goal, task: task}
  end

  defp evidence(result, rows) do
    %{
      "command" => "mise run check",
      "result" => result,
      "requirements" =>
        for({id, test, r} <- rows, do: %{"requirement" => id, "test" => test, "result" => r})
    }
  end

  defp all_pass, do: for(id <- ~w(R1 R2 R3), do: {id, "t #{id}", "passed"})

  defp review(scope, goal, task),
    do: widget!(scope, goal, task, "review", "findings", %{"findings" => []})

  defp implemented(scope, task),
    do: Planning.move_task(scope, Jarvis.Repo.reload(task), "implemented")

  defp reasons({:error, changeset}), do: errors_on(changeset).transition |> hd()

  describe "implemented" do
    setup %{task: task}, do: %{task: at_step!(task, "implementation")}

    test "is allowed when the check passed, every requirement passed, and a review exists", %{
      scope: scope,
      goal: goal,
      task: task
    } do
      widget!(scope, goal, task, "evidence", "evidence", evidence("passed", all_pass()))
      review(scope, goal, task)
      assert {:ok, %{step: "acceptance"}} = implemented(scope, task)
    end

    test "is refused when the check failed", %{scope: scope, goal: goal, task: task} do
      widget!(scope, goal, task, "evidence", "evidence", evidence("failed", all_pass()))
      review(scope, goal, task)
      assert reasons(implemented(scope, task)) =~ "the check failed"
    end

    test "is refused when a requirement has no test", %{scope: scope, goal: goal, task: task} do
      rows = Enum.reject(all_pass(), &(elem(&1, 0) == "R2"))
      widget!(scope, goal, task, "evidence", "evidence", evidence("passed", rows))
      review(scope, goal, task)
      assert reasons(implemented(scope, task)) == "R2 has no test"
    end

    test "is refused when a requirement's test failed", %{scope: scope, goal: goal, task: task} do
      rows = List.replace_at(all_pass(), 2, {"R3", "t R3", "failed"})
      widget!(scope, goal, task, "evidence", "evidence", evidence("passed", rows))
      review(scope, goal, task)
      assert reasons(implemented(scope, task)) == "R3's test failed"
    end

    test "is refused when the review report is missing", %{scope: scope, goal: goal, task: task} do
      widget!(scope, goal, task, "evidence", "evidence", evidence("passed", all_pass()))
      assert reasons(implemented(scope, task)) == "the review report is missing"
    end

    test "is refused without evidence", %{scope: scope, task: task} do
      assert reasons(implemented(scope, task)) =~ "evidence is missing"
    end
  end

  test "evidence rows must name the task's requirement cards", %{
    scope: scope,
    goal: goal,
    task: task
  } do
    task = at_step!(task, "implementation")

    assert {:error, {:widgets, [message]}} =
             Planning.apply_widget_ops(scope, goal, task, [
               %{
                 "op" => "add",
                 "section" => "evidence",
                 "kind" => "evidence",
                 "data" => evidence("passed", [{"R9", "t", "passed"}])
               }
             ])

    assert message =~ "no requirement card R9 on this task"
  end

  describe "handing Design over" do
    setup %{task: task}, do: %{task: at_step!(task, "design")}

    test "is refused without a review report", %{scope: scope, task: task} do
      assert {:error, changeset} = Planning.update_task(scope, task, %{"handoff" => true})
      assert %{handoff: [message]} = errors_on(changeset)
      assert message =~ "the review report is missing"
    end

    test "approve design is allowed whatever the review found", %{
      scope: scope,
      human: human,
      goal: goal,
      task: task
    } do
      widget!(
        scope,
        goal,
        task,
        "review",
        "findings",
        Jarvis.Planning.Catalog.example("findings")
      )

      {:ok, handed} = Planning.update_task(scope, task, %{"handoff" => true})

      assert {:ok, %{step: "implementation"}} =
               Planning.move_task(human, handed, "approve design")
    end
  end
end
