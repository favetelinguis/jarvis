defmodule Jarvis.PlanningTest do
  use Jarvis.DataCase, async: false

  import Jarvis.Fixtures

  alias Jarvis.Planning
  alias Jarvis.Planning.{Comment, Markdown}

  setup do
    repo = git_repo!()
    %{repo: repo, scope: agent_scope!(repo)}
  end

  describe "numbering and scoping" do
    test "goals are numbered per project and tasks per goal", %{scope: scope} do
      g1 = goal!(scope)
      g2 = goal!(scope)
      assert {g1.number, g2.number} == {1, 2}

      assert task!(scope, g1).number == 1
      assert task!(scope, g1).number == 2
      assert task!(scope, g2).number == 1
    end

    test "another project's goal is not found", %{scope: scope} do
      goal!(scope)
      other = agent_scope!(git_repo!())

      assert {:error, :not_found} = Planning.fetch_goal(other, 1)
      assert {:error, :not_found} = Planning.fetch_task(other, 1, 1)
    end
  end

  describe "task types" do
    test "a task without a type is a Feature in its first step", %{scope: scope} do
      task = task!(scope, goal!(scope))
      assert {task.type, task.step, task.previous_step} == {:feature, "requirements", nil}
    end

    test "each type starts in the first step of its lifecycle", %{scope: scope} do
      goal = goal!(scope)

      steps =
        for type <- ~w(research pr_review learn), do: task!(scope, goal, %{"type" => type}).step

      assert steps == ["question", "intake", "topic"]
    end

    test "an unknown type is rejected", %{scope: scope} do
      assert {:error, changeset} =
               Planning.create_task(scope, goal!(scope), %{"title" => "x", "type" => "epic"})

      assert %{type: [message]} = errors_on(changeset)
      assert message =~ "feature, research, pr_review, learn"
    end

    test "a task's type never changes", %{scope: scope} do
      task = task!(scope, goal!(scope))
      assert {:error, changeset} = Planning.update_task(scope, task, %{"type" => "research"})
      assert %{type: ["a task's type never changes"]} = errors_on(changeset)

      assert {:ok, _} =
               Planning.update_task(scope, task, %{
                 "type" => "feature",
                 "title" => "Same type is fine"
               })
    end
  end

  describe "update_task/3" do
    test "claim takes the task for the caller's worktree and release frees it", %{
      repo: repo,
      scope: scope
    } do
      goal = goal!(scope)
      {:ok, claimed} = Planning.update_task(scope, task!(scope, goal), %{"claim" => true})
      assert claimed.worktree.path == repo

      {:ok, released} = Planning.update_task(human_scope(scope), claimed, %{"claim" => false})
      assert released.worktree_id == nil
    end

    test "the human cannot claim, having no worktree", %{scope: scope} do
      task = task!(scope, goal!(scope))

      assert {:error, changeset} =
               Planning.update_task(human_scope(scope), task, %{"claim" => true})

      assert %{claim: [_]} = errors_on(changeset)
    end

    test "the changed task becomes the agent session's focus", %{scope: scope} do
      task = task!(scope, goal!(scope))
      {:ok, _} = Planning.update_task(scope, task, %{"title" => "Renamed"})

      [session] = Jarvis.Workspaces.list_sessions(scope.project)
      assert session.task_id == task.id
    end
  end

  describe "transitions" do
    setup %{scope: scope} do
      goal = goal!(scope)
      %{goal: goal, task: task!(scope, goal), human: human_scope(scope)}
    end

    test "the human moves a task along a human transition once the condition holds", %{
      scope: scope,
      goal: goal,
      task: task,
      human: human
    } do
      widget!(scope, goal, task, "requirements", "requirement", requirement("R1"))
      {:ok, widget} = Planning.fetch_widget(scope, hd(Planning.list_widgets(goal, task)).id)

      assert {:error, changeset} = Planning.move_task(human, task, "approve requirements")
      assert %{transition: ["R1 not confirmed"]} = errors_on(changeset)

      {:ok, _} = Planning.widget_action(human, widget, "confirm", %{})
      assert {:ok, moved} = Planning.move_task(human, task, "approve requirements")
      assert {moved.step, moved.previous_step} == {"design", "requirements"}
      assert %{summary: "Task 1.1: moved Requirements → Design"} = hd(Planning.list_events(scope))
    end

    test "a Feature cannot leave Requirements without a requirement card", %{
      task: task,
      human: human
    } do
      assert {:error, changeset} = Planning.move_task(human, task, "approve requirements")
      assert %{transition: ["Write at least one requirement card first"]} = errors_on(changeset)
    end

    test "an agent cannot take the human's decision, and is told where the button is", %{
      scope: scope,
      task: task
    } do
      assert {:error, changeset} = Planning.move_task(scope, task, "approve requirements")
      assert %{transition: [message]} = errors_on(changeset)
      assert message =~ ~s("approve requirements" is the human's decision)
      assert message =~ "/goals/1/tasks/1"
      assert Planning.fetch_task(scope, 1, 1) |> elem(1) |> Map.get(:step) == "requirements"
    end

    test "naming a transition that does not leave the step lists the ones that do", %{
      scope: scope,
      task: task
    } do
      assert {:error, changeset} = Planning.move_task(scope, task, "implemented")
      assert %{transition: [message]} = errors_on(changeset)
      assert message =~ ~s(no transition "implemented" out of Requirements)
      assert message =~ "allowed: approve requirements"
    end

    test "agent transitions work for an agent and loop back", %{scope: scope, task: task} do
      {:ok, task} = {:ok, at_step!(task, "design", task.step)}
      assert {:ok, task} = Planning.move_task(scope, task, "requirements question")
      assert {task.step, task.previous_step} == {"requirements", "design"}
    end

    test "force_step jumps anywhere in a POC goal and rejects unknown steps", %{
      scope: scope,
      goal: goal,
      task: task
    } do
      {:ok, _} = Planning.update_goal(scope, goal, %{"poc" => true})

      assert {:ok, %{step: "acceptance", previous_step: "requirements"}} =
               Planning.update_task(scope, task, %{"force_step" => "acceptance"})

      assert {:error, changeset} = Planning.update_task(scope, task, %{"force_step" => "nowhere"})
      assert %{force_step: [_]} = errors_on(changeset)
    end

    test "force_step is refused outside POC goals", %{scope: scope, task: task} do
      assert {:error, changeset} = Planning.update_task(scope, task, %{"force_step" => "done"})
      assert %{force_step: [message]} = errors_on(changeset)
      assert message =~ "only for POC goals"
    end

    test "done has no transitions out", %{scope: scope, task: task} do
      {:ok, task} = {:ok, at_step!(task, "done", task.step)}
      assert {:error, changeset} = Planning.move_task(scope, task, "accept")
      assert %{transition: [message]} = errors_on(changeset)
      assert message =~ "this step has none"
    end

    test "a gate quiz blocks its transition until every question is answered correctly", %{
      scope: scope,
      goal: goal,
      human: human
    } do
      learn = task!(scope, goal, %{"type" => "learn"})
      {:ok, learn} = {:ok, at_step!(learn, "check", learn.step)}

      quiz =
        widget!(scope, goal, learn, "check", "quiz", %{
          "mode" => "gate",
          "gates" => "passed",
          "questions" => [
            %{
              "id" => "q1",
              "prompt" => "?",
              "type" => "single",
              "options" => [
                %{"id" => "a", "text" => "x", "explanation" => "e"},
                %{"id" => "b", "text" => "y", "correct" => true, "explanation" => "e"}
              ]
            }
          ]
        })

      assert {:error, changeset} = Planning.move_task(human, learn, "passed")
      assert %{transition: [message]} = errors_on(changeset)
      assert message =~ "q1 not answered correctly"

      {:ok, _} =
        Planning.widget_action(human, quiz, "answer", %{"question" => "q1", "answer" => "b"})

      assert {:ok, %{step: "done"}} = Planning.move_task(human, learn, "passed")
    end
  end

  describe "apply_widget_ops/4" do
    setup %{scope: scope} do
      goal = goal!(scope)
      %{goal: goal, task: task!(scope, goal)}
    end

    test "adds, updates, moves, and deletes widgets, keeping ids stable", %{
      scope: scope,
      goal: goal,
      task: task
    } do
      {:ok, [a, b]} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{
            "op" => "add",
            "section" => "Requirements",
            "kind" => "requirement",
            "data" => requirement("R1")
          },
          %{
            "op" => "add",
            "section" => "requirements",
            "kind" => "requirement",
            "data" => requirement("R2"),
            "position" => 1
          }
        ])

      ids = fn -> Planning.list_widgets(goal, task) |> Enum.map(&{&1.id, &1.position}) end
      assert ids.() == [{b, 1}, {a, 2}]

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{"op" => "move", "id" => a, "position" => 1}
        ])

      assert ids.() == [{a, 1}, {b, 2}]

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{"op" => "update", "id" => "W#{a}", "data" => requirement("R1", "do better")}
        ])

      assert {:ok, %{data: %{"response" => "do better"}}} = Planning.fetch_widget(scope, a)

      {:ok, _} = Planning.apply_widget_ops(scope, goal, task, [%{"op" => "delete", "id" => a}])
      assert ids.() == [{b, 1}]
    end

    test "a failing op changes nothing and names the op and fields", %{
      scope: scope,
      goal: goal,
      task: task
    } do
      ops = [
        %{
          "op" => "add",
          "section" => "requirements",
          "kind" => "requirement",
          "data" => requirement("R1")
        },
        %{
          "op" => "add",
          "section" => "requirements",
          "kind" => "requirement",
          "data" => %{"pattern" => "sometimes"}
        }
      ]

      assert {:error, {:widgets, messages}} = Planning.apply_widget_ops(scope, goal, task, ops)
      assert Enum.any?(messages, &(&1 =~ "op 2 (add): pattern: must be one of"))
      assert Planning.list_widgets(goal, task) == []
    end

    test "unknown kinds and sections list the valid ones", %{scope: scope, goal: goal, task: task} do
      assert {:error, {:widgets, [kind]}} =
               Planning.apply_widget_ops(scope, goal, task, [
                 %{"op" => "add", "section" => "intent", "kind" => "chart", "data" => %{}}
               ])

      assert kind =~ "no widget kind \"chart\"; kinds: prose, callout"

      assert {:error, {:widgets, [section]}} =
               Planning.apply_widget_ops(scope, goal, task, [
                 %{
                   "op" => "add",
                   "section" => "Budget",
                   "kind" => "prose",
                   "data" => %{"text" => "x"}
                 }
               ])

      assert section =~ "no section \"Budget\"; sections: intent, requirements"
    end

    test "goals have their own sections", %{scope: scope, goal: goal} do
      assert {:ok, [_]} =
               Planning.apply_widget_ops(scope, goal, nil, [
                 %{
                   "op" => "add",
                   "section" => "glossary",
                   "kind" => "glossary_term",
                   "data" => Jarvis.Planning.Catalog.example("glossary_term")
                 }
               ])

      assert [%{section: "glossary", task_id: nil}] = Planning.list_widgets(goal, nil)
    end

    test "a widget of another task cannot be changed", %{scope: scope, goal: goal, task: task} do
      other = task!(scope, goal)
      widget = widget!(scope, goal, other, "intent", "prose", %{"text" => "x"})

      assert {:error, {:widgets, [message]}} =
               Planning.apply_widget_ops(scope, goal, task, [
                 %{"op" => "delete", "id" => widget.id}
               ])

      assert message =~ "no widget"
    end

    test "changes are broadcast", %{scope: scope, goal: goal, task: task} do
      Jarvis.Workspaces.subscribe(scope.project.id)
      widget!(scope, goal, task, "intent", "prose", %{"text" => "x"})
      assert_receive {:jarvis, :changed}
    end

    test "the agent reads widgets with their ids and parts", %{
      scope: scope,
      goal: goal,
      task: task
    } do
      widget = widget!(scope, goal, task, "examples", "examples")
      {:ok, task} = Planning.fetch_task(scope, goal.number, task.number)
      text = Markdown.task(task, Planning.list_widgets(goal, task))

      assert text =~ "# Task 1.1: A task"
      assert text =~ "**Type:** Feature"
      assert text =~ "#### W#{widget.id} · examples"
      assert text =~ "row:r2"

      assert text =~
               ~s|"approve requirements" → Design, moved by the human only (a button on the task page; never make it yourself) — blocked: Write at least one requirement card first|

      assert text =~ "**Turn:** the agent's (/specify)."
      assert text =~ "**Sections you may write in this step:** intent, requirements,"

      assert text =~ "## Intent (`intent`)\n\n_Nothing yet._"
    end
  end

  describe "anchored comments" do
    setup %{scope: scope} do
      goal = goal!(scope)
      task = task!(scope, goal, %{"claim" => true})
      widget = widget!(scope, goal, task, "examples", "examples")
      %{goal: goal, task: task, widget: widget, human: human_scope(scope)}
    end

    test "record the anchor and what it pointed at", %{
      goal: goal,
      task: task,
      widget: widget,
      human: human
    } do
      {:ok, comment} =
        Planning.add_comment(human, goal, task, %{
          "body" => "why?",
          "widget" => widget.id,
          "part" => "row:r2"
        })

      assert comment.anchor_label == "Examples table W#{widget.id} · Row 2"
      assert comment.anchor_text =~ "Seats 2 → rejected"
      assert comment.deliver
    end

    test "reject a widget or part that does not exist", %{
      goal: goal,
      task: task,
      widget: widget,
      human: human
    } do
      assert {:error, cs} =
               Planning.add_comment(human, goal, task, %{"body" => "x", "widget" => 0})

      assert %{widget: [_]} = errors_on(cs)

      assert {:error, cs} =
               Planning.add_comment(human, goal, task, %{
                 "body" => "x",
                 "widget" => widget.id,
                 "part" => "row:zzz"
               })

      assert %{part: [_]} = errors_on(cs)
    end

    test "an agent's reply joins the thread it answers", %{
      scope: scope,
      goal: goal,
      task: task,
      widget: widget,
      human: human
    } do
      {:ok, asked} =
        Planning.add_comment(human, goal, task, %{
          "body" => "why?",
          "widget" => widget.id,
          "part" => "row:r2"
        })

      {:ok, reply} =
        Planning.add_comment(scope, goal, task, %{"body" => "because", "reply_to" => asked.id})

      assert {reply.widget_id, reply.part, reply.anchor_label} ==
               {widget.id, "row:r2", asked.anchor_label}

      refute reply.deliver
    end

    test "changing a widget with a thread adds a 'Widget updated' entry", %{
      scope: scope,
      goal: goal,
      task: task,
      widget: widget,
      human: human
    } do
      {:ok, _} = Planning.add_comment(human, goal, task, %{"body" => "x", "widget" => widget.id})

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [
          %{"op" => "update", "id" => widget.id, "data" => widget.data}
        ])

      assert %Comment{author: :system, body: "Widget updated", widget_id: id} =
               List.last(Repo.all(Comment))

      assert id == widget.id
    end

    test "deleting the widget keeps the comment with its anchor", %{
      scope: scope,
      goal: goal,
      task: task,
      widget: widget,
      human: human
    } do
      {:ok, comment} =
        Planning.add_comment(human, goal, task, %{
          "body" => "x",
          "widget" => widget.id,
          "part" => "row:r1"
        })

      {:ok, _} =
        Planning.apply_widget_ops(scope, goal, task, [%{"op" => "delete", "id" => widget.id}])

      kept = Repo.get!(Comment, comment.id)

      assert {kept.widget_id, kept.anchor_label, kept.anchor_text =~ "Plan free"} ==
               {nil, comment.anchor_label, true}
    end

    test "are not part of the inbox", %{
      repo: repo,
      scope: scope,
      goal: goal,
      task: task,
      widget: widget,
      human: human
    } do
      session = agent_scope!(repo, "late-but-same-worktree")

      {:ok, _} =
        Planning.add_comment(human, goal, task, %{"body" => "anchored", "widget" => widget.id})

      {:ok, _} = Planning.add_comment(human, goal, task, %{"body" => "plain"})

      assert {:ok, [%{body: "plain"}]} =
               Planning.take_inbox(%{
                 session
                 | agent_session: %{session.agent_session | inbox_cursor: 0}
               })

      _ = scope
    end
  end

  describe "the listening session" do
    setup %{repo: repo, scope: scope} do
      goal = goal!(scope)
      task = task!(scope, goal, %{"claim" => true})
      %{goal: goal, task: task, repo: repo}
    end

    test "is the session focused on the task, else one in its claiming worktree", %{
      repo: repo,
      scope: scope,
      goal: goal,
      task: task
    } do
      assert %{pi_session_id: id} = Planning.listening_session(scope.project, goal, task)
      assert id == scope.agent_session.pi_session_id

      # An unrelated session in another worktree, focused on nothing, never listens.
      elsewhere = agent_scope!(worktree!(repo, "other"), "elsewhere")
      other_task = task!(elsewhere, goal)
      other = Planning.listening_session(scope.project, goal, other_task)
      assert other.pi_session_id == "elsewhere"
    end

    test "is nobody when no live session works on it", %{repo: repo, scope: scope, goal: goal} do
      unfocused = agent_scope!(worktree!(repo, "idle"), "unfocused")
      loose = task!(scope, goal)
      {:ok, loose} = Planning.update_task(human_scope(scope), loose, %{"title" => "Loose"})
      Jarvis.Repo.update_all(Jarvis.Workspaces.AgentSession, set: [task_id: nil])
      _ = unfocused
      assert Planning.listening_session(scope.project, goal, loose) == nil
    end

    test "for a goal is a session focused on one of its tasks", %{scope: scope, goal: goal} do
      assert %{pi_session_id: _} = Planning.listening_session(scope.project, goal, nil)
    end

    test "take_wake hands anchored comments to the listening session once", %{
      scope: scope,
      goal: goal,
      task: task
    } do
      widget = widget!(scope, goal, task, "intent", "prose", %{"text" => "x"})

      {:ok, _} =
        Planning.add_comment(human_scope(scope), goal, task, %{
          "body" => "change this",
          "widget" => widget.id
        })

      assert {:ok, [%{body: "change this"}]} = Planning.take_wake(scope)
      assert {:ok, []} = Planning.take_wake(scope)
    end

    test "take_wake leaves comments for sessions that are not listening", %{
      repo: repo,
      scope: scope,
      goal: goal,
      task: task
    } do
      widget = widget!(scope, goal, task, "intent", "prose", %{"text" => "x"})

      {:ok, _} =
        Planning.add_comment(human_scope(scope), goal, task, %{
          "body" => "hello",
          "widget" => widget.id
        })

      bystander = agent_scope!(worktree!(repo, "bystander"), "bystander")
      assert {:ok, []} = Planning.take_wake(bystander)
      assert {:ok, [_]} = Planning.take_wake(scope)
    end

    test "comments wait while nobody listens and are delivered once a session does", %{
      repo: repo,
      scope: scope,
      goal: goal,
      task: task
    } do
      widget = widget!(scope, goal, task, "intent", "prose", %{"text" => "x"})
      Jarvis.Workspaces.set_state(scope, :ended)

      {:ok, _} =
        Planning.add_comment(human_scope(scope), goal, task, %{
          "body" => "anyone?",
          "widget" => widget.id
        })

      assert Planning.listening_session(scope.project, goal, task) == nil
      assert {:ok, []} = Planning.take_wake(scope)

      newcomer = agent_scope!(repo, "newcomer")
      Planning.update_task(newcomer, task, %{"title" => "Taken up"})

      newcomer = %{
        newcomer
        | agent_session:
            Jarvis.Repo.get!(Jarvis.Workspaces.AgentSession, newcomer.agent_session.id)
      }

      assert {:ok, [%{body: "anyone?"}]} = Planning.take_wake(newcomer)
    end

    test "the wake message names the anchor and how to answer", %{
      scope: scope,
      goal: goal,
      task: task
    } do
      widget = widget!(scope, goal, task, "examples", "examples")

      {:ok, _} =
        Planning.add_comment(human_scope(scope), goal, task, %{
          "body" => "Is row 2 right?",
          "widget" => widget.id,
          "part" => "row:r2"
        })

      {:ok, comments} = Planning.take_wake(scope)
      text = Markdown.wake(comments)

      assert text =~ "on Task 1.1 — Examples table W#{widget.id} · Row 2"
      assert text =~ "part `row:r2`"
      assert text =~ "> Plan free, Seats 2 → rejected"
      assert text =~ "Is row 2 right?"
      assert text =~ "reply_to"
    end
  end

  describe "take_inbox/1" do
    test "delivers the human's plain comments once, to the sessions concerned", %{
      repo: repo,
      scope: scope
    } do
      here = agent_scope!(repo, "here")
      elsewhere = agent_scope!(worktree!(repo, "other"), "elsewhere")
      human = human_scope(scope)

      goal = goal!(scope)
      mine = task!(here, goal, %{"claim" => true})
      open = task!(scope, goal)

      {:ok, _} = Planning.add_comment(human, goal, nil, %{"body" => "on the goal"})
      {:ok, _} = Planning.add_comment(human, goal, mine, %{"body" => "on a claimed task"})
      {:ok, _} = Planning.add_comment(human, goal, open, %{"body" => "on an open task"})
      {:ok, _} = Planning.add_comment(here, goal, mine, %{"body" => "agent note"})

      bodies = fn scope -> scope |> Planning.take_inbox() |> elem(1) |> Enum.map(& &1.body) end

      assert bodies.(here) == ["on the goal", "on a claimed task", "on an open task"]
      assert bodies.(elsewhere) == ["on the goal", "on an open task"]
      assert bodies.(agent_scope!(repo, "here")) == []
    end

    test "a new session is not shown comments made before it existed", %{repo: repo, scope: scope} do
      goal = goal!(scope)
      {:ok, _} = Planning.add_comment(human_scope(scope), goal, nil, %{"body" => "old"})
      assert {:ok, []} = Planning.take_inbox(agent_scope!(repo, "late"))
    end
  end

  describe "POC status" do
    test "an agent sets it but only the human clears it", %{scope: scope} do
      goal = goal!(scope)
      refute goal.poc

      assert {:ok, goal} = Planning.update_goal(scope, goal, %{"poc" => true})
      assert goal.poc

      assert {:error, changeset} = Planning.update_goal(scope, goal, %{"poc" => false})
      assert %{poc: [_]} = errors_on(changeset)

      assert {:ok, cleared} = Planning.update_goal(human_scope(scope), goal, %{"poc" => false})
      refute cleared.poc
    end
  end

  test "changes are broadcast to the project's viewers", %{scope: scope} do
    Jarvis.Workspaces.subscribe(scope.project.id)
    goal!(scope)
    assert_receive {:jarvis, :changed}
  end

  test "the catalog text lists every widget kind with an example", %{scope: scope} do
    _ = scope
    text = Markdown.catalog()
    for kind <- Jarvis.Planning.Catalog.kinds(), do: assert(text =~ "### #{kind} —")
    assert text =~ "### Feature task sections and recommended widgets"
  end
end
