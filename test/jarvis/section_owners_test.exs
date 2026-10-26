defmodule Jarvis.SectionOwnersTest do
  @moduledoc "Each step owns the sections an agent may write while a task is in it."
  use Jarvis.DataCase, async: false

  import Jarvis.Fixtures

  alias Jarvis.Planning
  alias Jarvis.Planning.TaskType

  setup do
    scope = agent_scope!(git_repo!())
    %{scope: scope, human: human_scope(scope), goal: goal!(scope)}
  end

  defp add(section),
    do: %{"op" => "add", "section" => section, "kind" => "prose", "data" => %{"text" => "x"}}

  test "a Feature's steps own the sections of the table" do
    spec = ~w(intent requirements examples constraints assumptions out_of_scope open_questions)

    assert TaskType.owned_sections(:feature, "requirements") == spec
    assert TaskType.owned_sections(:feature, "design") == spec ++ ~w(sketch tests review)
    assert TaskType.owned_sections(:feature, "implementation") == ~w(sketch tests review evidence)
    assert TaskType.owned_sections(:feature, "acceptance") == []
    assert TaskType.owned_sections(:feature, "done") == []
  end

  test "every section of every type is owned by some step, and every owned section exists" do
    for type <- TaskType.keys() do
      keys = Enum.map(TaskType.sections(type), &elem(&1, 0))

      for {step, _, _} <- TaskType.steps(type),
          section <- TaskType.owned_sections(type, step),
          do: assert(section in keys, "#{type} #{step} owns unknown section #{section}")

      for key <- keys,
          do: assert(TaskType.owning_steps(type, key) != [], "#{type} #{key} has no owner")
    end
  end

  test "an agent may write an owned section", %{scope: scope, goal: goal} do
    task = at_step!(task!(scope, goal), "implementation")
    assert {:ok, [_]} = Planning.apply_widget_ops(scope, goal, task, [add("sketch")])
  end

  test "an agent is refused a section its step does not own, and the whole call fails", %{
    scope: scope,
    goal: goal
  } do
    task = at_step!(task!(scope, goal), "acceptance")

    assert {:error, {:widgets, [message]}} =
             Planning.apply_widget_ops(scope, goal, task, [add("sketch")])

    assert message =~ "section sketch: the step Acceptance does not let an agent write it"
    assert message =~ "steps that do: Design, Implementation"
    assert Planning.list_widgets(goal, task) == []
  end

  test "update, move, delete, and judge are refused outside the owning step", %{
    scope: scope,
    goal: goal
  } do
    task = task!(scope, goal)
    widget = widget!(scope, goal, task, "sketch", "prose", %{"text" => "sketch"})
    quiz = widget!(scope, goal, task, "tests", "quiz", Jarvis.Planning.Catalog.example("quiz"))

    for op <- [
          %{"op" => "update", "id" => widget.id, "data" => %{"text" => "y"}},
          %{"op" => "move", "id" => widget.id, "section" => "intent"},
          %{"op" => "delete", "id" => widget.id},
          %{
            "op" => "judge",
            "id" => quiz.id,
            "question" => "q2",
            "correct" => true,
            "explanation" => "e"
          }
        ] do
      assert {:error, {:widgets, [message]}} = Planning.apply_widget_ops(scope, goal, task, [op])
      assert message =~ "does not let an agent write it"
    end
  end

  test "moving a widget into a section the step does not own is refused", %{
    scope: scope,
    goal: goal
  } do
    task = task!(scope, goal)
    widget = widget!(scope, goal, task, "intent", "prose", %{"text" => "x"})

    assert {:error, {:widgets, [message]}} =
             Planning.apply_widget_ops(scope, goal, task, [
               %{"op" => "move", "id" => widget.id, "section" => "sketch"}
             ])

    assert message =~ "section sketch"
  end

  test "the human's own actions work in any step", %{scope: scope, human: human, goal: goal} do
    task = at_step!(task!(scope, goal), "done")
    widget = widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))

    assert {:ok, %{human: %{"confirmed" => true}}} =
             Planning.widget_action(human, widget, "confirm", %{})
  end

  test "goal sections are not limited by any step", %{scope: scope, goal: goal} do
    assert {:ok, [_]} = Planning.apply_widget_ops(scope, goal, nil, [add("intent")])
  end

  test "force_step is refused outside a POC goal and the task stays", %{scope: scope, goal: goal} do
    task = task!(scope, goal)
    assert {:error, _} = Planning.update_task(scope, task, %{"force_step" => "done"})
    assert Jarvis.Repo.reload(task).step == "requirements"

    {:ok, _} = Planning.update_goal(scope, goal, %{"poc" => true})
    assert {:ok, %{step: "done"}} = Planning.update_task(scope, task, %{"force_step" => "done"})
  end
end
