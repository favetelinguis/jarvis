defmodule Jarvis.YourViewTest do
  @moduledoc "In a PR review the human writes their own concerns before seeing the agent's findings."
  use Jarvis.DataCase, async: false

  import Jarvis.Fixtures

  alias Jarvis.{Planning, Repo, Workspaces}
  alias Jarvis.Planning.{Catalog, Markdown}

  setup do
    scope = agent_scope!(git_repo!())
    goal = goal!(scope)
    task = at_step!(task!(scope, goal, %{"type" => "pr_review"}), "findings")
    Workspaces.focus(scope, task.id)
    %{scope: scope, human: human_scope(scope), goal: goal, task: task}
  end

  test "the findings wait for the human's view until it is saved or skipped", %{
    human: human,
    task: task
  } do
    assert Planning.picture_pending?(task)
    {:ok, skipped} = Planning.save_picture(human, task, nil)
    refute Planning.picture_pending?(skipped)
  end

  test "saving the view shows the findings and delivers it to the listening session, again when changed",
       %{scope: scope, human: human, task: task} do
    {:ok, saved} =
      Planning.save_picture(
        human,
        task,
        "timeout missing in the client\n\nmigration cannot be undone\n"
      )

    refute Planning.picture_pending?(saved)

    assert saved.picture["concerns"] == [
             %{"id" => "c1", "text" => "timeout missing in the client"},
             %{"id" => "c2", "text" => "migration cannot be undone"}
           ]

    {:ok, [message]} = Planning.take_wake(scope)
    text = Markdown.wake([message])
    assert text =~ "c1: timeout missing in the client"
    assert text =~ "view_matches"

    {:ok, _} = Planning.save_picture(human, saved, "only one concern")
    {:ok, [changed]} = Planning.take_wake(scope)
    assert changed.body =~ "(changed)"
    assert changed.body =~ "c1: only one concern"
  end

  test "an empty view is refused", %{human: human, task: task} do
    assert {:error, :empty} = Planning.save_picture(human, task, "  \n ")
    assert Planning.picture_pending?(Repo.reload(task))
  end

  test "the agent records matches, the human changes one, and an agent update keeps it", %{
    scope: scope,
    human: human,
    goal: goal,
    task: task
  } do
    {:ok, [id]} =
      Planning.apply_widget_ops(scope, goal, task, [
        %{
          "op" => "add",
          "section" => "picture",
          "kind" => "view_matches",
          "data" => Catalog.example("view_matches")
        }
      ])

    {:ok, widget} = Planning.fetch_widget(scope, id)
    assert Catalog.view_matches(widget) == %{"f1" => "c1", "f2" => nil}

    {:ok, widget} =
      Planning.widget_action(human, widget, "match", %{"finding" => "f2", "concern" => "c2"})

    {:ok, widget2} =
      Planning.widget_action(human, widget, "match", %{"finding" => "f1", "concern" => "none"})

    assert Catalog.view_matches(widget2) == %{"f1" => nil, "f2" => "c2"}

    {:ok, _} =
      Planning.apply_widget_ops(scope, goal, task, [
        %{"op" => "update", "id" => id, "data" => Catalog.example("view_matches")}
      ])

    {:ok, after_update} = Planning.fetch_widget(scope, id)
    assert Catalog.view_matches(after_update) == %{"f1" => nil, "f2" => "c2"}
  end

  test "a PR review already in Findings before the change shows its findings at once", %{
    scope: scope,
    goal: goal
  } do
    old =
      task!(scope, goal, %{"type" => "pr_review"})
      |> at_step!("findings")
      |> Ecto.Changeset.change(picture: %{"state" => "not_asked"})
      |> Repo.update!()

    refute Planning.picture_pending?(old)
  end
end
