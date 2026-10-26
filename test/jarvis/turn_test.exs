defmodule Jarvis.TurnTest do
  @moduledoc "Whose turn it is in a task, and how the turn passes between the human and the agent."
  use Jarvis.DataCase, async: false

  import Jarvis.Fixtures

  alias Jarvis.Planning
  alias Jarvis.Planning.{Markdown, TaskType}

  setup do
    scope = agent_scope!(git_repo!())
    %{scope: scope, human: human_scope(scope), goal: goal!(scope)}
  end

  @table [
    {:feature, "requirements", {:agent, "/specify"}},
    {:feature, "design", {:agent, "/design"}},
    {:feature, "implementation", {:agent, "/impl"}},
    {:feature, "acceptance", :human},
    {:feature, "done", :none},
    {:research, "question", {:agent, "/research"}},
    {:research, "investigation", {:agent, "/research"}},
    {:research, "findings", :human},
    {:research, "done", :none},
    {:pr_review, "intake", {:agent, "/pr-review"}},
    {:pr_review, "explanation", {:agent, "/pr-review"}},
    {:pr_review, "quiz", :human},
    {:pr_review, "findings", :human},
    {:pr_review, "done", :none},
    {:learn, "topic", {:agent, "/learn"}},
    {:learn, "explanation", {:agent, "/learn"}},
    {:learn, "check", :human},
    {:learn, "done", :none}
  ]

  test "a step gives the turn to whoever the table names when the task enters it", %{
    scope: scope,
    goal: goal
  } do
    for {type, step, turn} <- @table do
      task = at_step!(task!(scope, goal, %{"type" => Atom.to_string(type)}), step)
      assert Planning.turn(task) == turn, "#{type} #{step}"
    end
  end

  test "a move resets the turn to the new step's owner", %{scope: scope, human: human, goal: goal} do
    task = task!(scope, goal)
    widget = widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
    {:ok, _} = Planning.widget_action(human, widget, "confirm", %{})
    {:ok, handed} = Planning.update_task(scope, task, %{"handoff" => true})
    assert Planning.turn(handed) == :human

    {:ok, moved} = Planning.move_task(human, handed, "approve requirements")
    assert Planning.turn(moved) == {:agent, "/design"}
  end

  describe "handing a step over" do
    test "gives the turn to the human without changing the step", %{scope: scope, goal: goal} do
      task = task!(scope, goal, %{"type" => "research"})
      {:ok, handed} = Planning.update_task(scope, task, %{"handoff" => true})
      assert {handed.step, Planning.turn(handed)} == {"question", :human}
      assert %{summary: "Task 1.1: handed over to you"} = hd(Planning.list_events(scope))
    end

    test "is refused in a step that is not handed over, naming the steps that are", %{
      scope: scope,
      goal: goal
    } do
      task = at_step!(task!(scope, goal), "implementation")
      assert {:error, changeset} = Planning.update_task(scope, task, %{"handoff" => true})
      assert %{handoff: [message]} = errors_on(changeset)
      assert message =~ "Implementation cannot be handed over"
      assert message =~ "steps that are handed over: Requirements, Design"
    end

    test "is refused when it is already the human's turn", %{scope: scope, goal: goal} do
      task = task!(scope, goal, %{"type" => "learn"}) |> at_step!("explanation")
      {:ok, handed} = Planning.update_task(scope, task, %{"handoff" => true})
      assert {:error, changeset} = Planning.update_task(scope, handed, %{"handoff" => true})
      assert %{handoff: [message]} = errors_on(changeset)
      assert message =~ "already the human's turn"
      assert message =~ "steps that are handed over: Explanation"
    end
  end

  test "answering every quiz question in Quiz gives the turn to the agent", %{
    scope: scope,
    human: human,
    goal: goal
  } do
    task = at_step!(task!(scope, goal, %{"type" => "pr_review"}), "quiz")

    quiz =
      widget!(scope, goal, task, "quiz", "quiz", %{
        "mode" => "feedback",
        "questions" =>
          for id <- ~w(q1 q2) do
            %{
              "id" => id,
              "prompt" => "?",
              "type" => "single",
              "options" => [
                %{"id" => "a", "text" => "x", "correct" => true, "explanation" => "e"},
                %{"id" => "b", "text" => "y", "explanation" => "e"}
              ]
            }
          end
      })

    {:ok, quiz} =
      Planning.widget_action(human, quiz, "answer", %{"question" => "q1", "answer" => "b"})

    assert Planning.turn(Jarvis.Repo.reload(task)) == :human

    {:ok, _} =
      Planning.widget_action(human, quiz, "answer", %{"question" => "q2", "answer" => "a"})

    assert Planning.turn(Jarvis.Repo.reload(task)) == {:agent, "/pr-review"}
  end

  test "skipping the quiz gives the turn to the agent", %{scope: scope, human: human, goal: goal} do
    task = at_step!(task!(scope, goal, %{"type" => "pr_review"}), "quiz")
    {:ok, skipped} = Planning.skip_quiz(human, task)
    assert Planning.turn(skipped) == {:agent, "/pr-review"}
  end

  test "sending work back within the step gives the turn to the agent", %{
    scope: scope,
    human: human,
    goal: goal
  } do
    task = at_step!(task!(scope, goal), "design")
    widget!(scope, goal, task, "review", "findings", %{"findings" => []})
    {:ok, handed} = Planning.update_task(scope, task, %{"handoff" => true})

    {:ok, back} =
      Planning.move_task(human, handed, "request design changes", %{"comment" => "smaller API"})

    assert {back.step, Planning.turn(back)} == {"design", {:agent, "/design"}}
  end

  test "every move the human makes is delivered with its name and the new step", %{
    scope: scope,
    human: human,
    goal: goal
  } do
    task = task!(scope, goal, %{"type" => "research"})
    Jarvis.Workspaces.focus(scope, task.id)
    {:ok, _} = Planning.move_task(human, task, "approve question")
    {:ok, [move]} = Planning.take_wake(scope)

    assert Markdown.wake([move]) =~
             ~s(The human moved Task 1.1: "approve question" → Investigation)

    refute Markdown.wake([move]) =~ "Their comment"
  end

  test "jarvis_read says whose turn it is and how to hand over", %{scope: scope, goal: goal} do
    task = task!(scope, goal)

    text =
      Markdown.task(Jarvis.Repo.preload(task, [:goal, :worktree, comments: :agent_session]), [])

    assert text =~ "**Turn:** the agent's (/specify)"
    assert text =~ "`handoff: true`"
    assert TaskType.handoff_steps(:feature) == ~w(requirements design)
  end
end
