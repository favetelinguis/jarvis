defmodule Jarvis.DecisionsTest do
  @moduledoc "Every decision that is the human's is a button no agent can press."
  use Jarvis.DataCase, async: false

  import Jarvis.Fixtures

  alias Jarvis.{Planning, Workspaces}
  alias Jarvis.Planning.{Markdown, TaskType}

  setup do
    repo = git_repo!()
    scope = agent_scope!(repo)
    goal = goal!(scope)
    %{scope: scope, human: human_scope(scope), goal: goal}
  end

  test "each type offers exactly the transitions of the table, with mover and comment" do
    table = %{
      feature: [
        {"requirements", "approve requirements", "design", :human, false},
        {"design", "requirements question", "requirements", :agent, false},
        {"design", "approve design", "implementation", :human, false},
        {"design", "request design changes", "design", :human, true},
        {"implementation", "implemented", "acceptance", :agent, false},
        {"acceptance", "accept", "done", :human, false},
        {"acceptance", "request changes", "implementation", :human, true},
        {"acceptance", "spec issue", "acceptance", :human, true}
      ],
      research: [
        {"question", "approve question", "investigation", :human, false},
        {"investigation", "findings ready", "findings", :agent, false},
        {"findings", "accept", "done", :human, false},
        {"findings", "dig deeper", "investigation", :human, true}
      ],
      pr_review: [
        {"intake", "start explanation", "explanation", :agent, false},
        {"explanation", "ready for the quiz", "quiz", :human, false},
        {"quiz", "findings ready", "findings", :agent, false},
        {"findings", "give verdict", "done", :human, false},
        {"findings", "look again", "explanation", :human, true},
        {"done", "re-review", "findings", :human, false}
      ],
      learn: [
        {"topic", "explain", "explanation", :agent, false},
        {"explanation", "check understanding", "check", :human, false},
        {"check", "passed", "done", :human, false},
        {"check", "gaps found", "explanation", :human, true}
      ]
    }

    for {type, rows} <- table do
      actual =
        for t <- TaskType.transitions(type),
            do: {t.from, t.name, t.to, t.mover, Map.get(t, :comment, false)}

      assert Enum.sort(actual) == Enum.sort(rows), "#{type} transitions differ from the table"
    end

    assert Enum.map(TaskType.steps(:feature), &elem(&1, 0)) ==
             ~w(requirements design implementation acceptance done)
  end

  test "an agent is refused every human transition and the task stays", %{
    scope: scope,
    goal: goal
  } do
    for {type, _} <- TaskType.all(), t <- TaskType.transitions(type), t.mover == :human do
      task = at_step!(task!(scope, goal, %{"type" => Atom.to_string(type)}), t.from)

      assert {:error, changeset} = Planning.move_task(scope, task, t.name, %{"comment" => "x"})
      assert %{transition: [message]} = errors_on(changeset)
      assert message =~ ~s("#{t.name}" is the human's decision)
      assert message =~ "/goals/#{goal.number}/tasks/#{task.number}"
      assert Jarvis.Repo.reload(task).step == t.from
    end
  end

  describe "sending work back" do
    setup %{scope: scope, goal: goal} do
      %{task: at_step!(task!(scope, goal), "acceptance")}
    end

    test "is refused without a comment and leaves the task in its step", %{
      human: human,
      task: task
    } do
      for comment <- [nil, "", "   "] do
        assert {:error, changeset} =
                 Planning.move_task(human, task, "request changes", %{"comment" => comment})

        assert %{comment: [message]} = errors_on(changeset)
        assert message =~ "needs a comment that says what to change"
      end

      assert Jarvis.Repo.reload(task).step == "acceptance"
    end

    test "keeps the comment with the transition's name and delivers it to the listening session",
         %{scope: scope, human: human, task: task, goal: goal} do
      {:ok, _} = Planning.update_task(scope, task, %{"claim" => true})

      {:ok, moved} =
        Planning.move_task(human, task, "request changes", %{"comment" => "R2 is not met"})

      assert moved.step == "implementation"

      {:ok, task} = Planning.fetch_task(human, goal.number, task.number)
      move = Enum.find(task.comments, & &1.transition)

      assert {move.transition, move.body, move.to_step} ==
               {"request changes", "R2 is not met", "implementation"}

      assert {:ok, []} = Planning.take_inbox(scope)
      assert {:ok, [delivered]} = Planning.take_wake(scope)
      text = Markdown.wake([delivered])
      assert text =~ ~s(The human moved Task 1.1: "request changes" → Implementation)
      assert text =~ "R2 is not met"
      assert {:ok, []} = Planning.take_wake(scope)
    end

    test "a move waits for a listening session and wakes none", %{
      human: human,
      task: task,
      goal: goal
    } do
      {:ok, _} = Planning.move_task(human, task, "request changes", %{"comment" => "fix it"})
      {:ok, task} = Planning.fetch_task(human, goal.number, task.number)
      move = Enum.find(task.comments, & &1.transition)
      assert move.deliver and is_nil(move.delivered_at)
    end

    test "spec issue splits a new Feature task off and leaves the original in Acceptance", %{
      human: human,
      task: task,
      goal: goal
    } do
      assert {:error, changeset} =
               Planning.move_task(human, task, "spec issue", %{"comment" => "R3 is wrong"})

      assert %{new_title: [_]} = errors_on(changeset)

      {:ok, kept} =
        Planning.move_task(human, task, "spec issue", %{
          "comment" => "R3 asks for the wrong limit",
          "new_title" => "Fix the limit"
        })

      assert kept.step == "acceptance"
      {:ok, goal} = Planning.fetch_goal(human, goal.number)
      new = Enum.find(goal.tasks, &(&1.title == "Fix the limit"))
      assert {new.type, new.step} == {:feature, "requirements"}

      [intent] = Planning.list_widgets(goal, new)
      assert intent.section == "intent"
      assert intent.data["text"] =~ "R3 asks for the wrong limit"
      assert intent.data["text"] =~ "/goals/#{goal.number}/tasks/#{task.number}"
    end
  end

  describe "the quiz of a PR review" do
    setup %{scope: scope, goal: goal} do
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

      %{task: task, quiz: quiz}
    end

    test "findings ready is refused while a question is unanswered, naming it", %{
      scope: scope,
      human: human,
      task: task,
      quiz: quiz
    } do
      {:ok, _} =
        Planning.widget_action(human, quiz, "answer", %{"question" => "q1", "answer" => "a"})

      assert {:error, changeset} = Planning.move_task(scope, task, "findings ready")
      assert %{transition: [message]} = errors_on(changeset)
      assert message =~ "q2 not answered"
      refute message =~ "q1"
    end

    test "skip quiz lets findings ready through with questions unanswered", %{
      scope: scope,
      human: human,
      task: task
    } do
      assert {:error, _} =
               Planning.skip_quiz(
                 scope |> Map.put(:agent_session, nil),
                 at_step!(task, "findings")
               )

      {:ok, skipped} = Planning.skip_quiz(human, task)
      assert skipped.quiz_skipped
      assert {:ok, %{step: "findings"}} = Planning.move_task(scope, skipped, "findings ready")
    end
  end

  test "a new session hears a move made before it listened", %{
    human: human,
    goal: goal,
    scope: scope
  } do
    task = at_step!(task!(scope, goal), "acceptance")
    {:ok, _} = Planning.move_task(human, task, "request changes", %{"comment" => "later"})
    {:ok, _} = Planning.update_task(scope, Jarvis.Repo.reload(task), %{"claim" => true})
    late = agent_scope!(scope.worktree.path)
    Workspaces.focus(late, task.id)
    assert {:ok, [_]} = Planning.take_wake(late)
  end
end
