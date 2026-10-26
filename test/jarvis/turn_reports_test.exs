defmodule Jarvis.TurnReportsTest do
  @moduledoc "What an agent turn changed on the board, shown once the turn ends."
  use Jarvis.DataCase, async: false

  import Jarvis.Fixtures

  alias Jarvis.{Planning, Workspaces}
  alias Jarvis.Planning.Report

  setup do
    scope = agent_scope!(git_repo!())
    goal = goal!(scope)
    task = task!(scope, goal)
    %{scope: Workspaces.set_state(scope, :working), goal: goal, task: task}
  end

  defp ops(scope, goal, task, ops, meta \\ %{}),
    do: {:ok, _} = Planning.apply_widget_ops(scope, goal, task, ops, meta)

  defp add(section, kind, data),
    do: %{"op" => "add", "section" => section, "kind" => kind, "data" => data}

  test "a report shows once the turn ends, with each widget before and after", %{
    scope: scope,
    goal: goal,
    task: task
  } do
    {:ok, [req, gone]} =
      Planning.apply_widget_ops(scope, goal, task, [
        add("requirements", "requirement", requirement("R1")),
        add("intent", "prose", %{"text" => "old"})
      ])

    assert Planning.list_reports(goal, task) == {[], []}
    Workspaces.set_state(scope, :idle)
    scope = Workspaces.set_state(scope, :working)

    ops(scope, goal, task, [
      %{"op" => "update", "id" => req, "data" => requirement("R1", "do better")},
      %{"op" => "delete", "id" => gone},
      add("intent", "prose", %{"text" => "new"})
    ])

    Workspaces.set_state(scope, :idle)
    {[latest, first], []} = Planning.list_reports(goal, task)

    assert [%{"action" => "added"}, %{"action" => "added"}] = Report.items(first)

    [changed, removed, added] = Report.items(latest)

    assert {changed["action"], changed["before"]["response"], changed["after"]["response"]} ==
             {"updated", "do the thing", "do better"}

    assert {removed["action"], removed["before"]["text"], removed["after"]} ==
             {"deleted", "old", nil}

    assert {added["action"], added["after"]["text"]} == {"added", "new"}
  end

  test "repeated changes to one widget in a turn are one entry, first before and last after", %{
    scope: scope,
    goal: goal,
    task: task
  } do
    widget = widget!(scope, goal, task, "intent", "prose", %{"text" => "v1"})

    for v <- ~w(v2 v3),
        do:
          ops(
            scope,
            goal,
            task,
            [%{"op" => "update", "id" => widget.id, "data" => %{"text" => v}}],
            %{"reason" => "to #{v}"}
          )

    Workspaces.set_state(scope, :idle)
    {[report], _} = Planning.list_reports(goal, task)

    assert [
             %{
               "before" => %{"text" => "v1"},
               "after" => %{"text" => "v3"},
               "reasons" => ["to v2", "to v3"]
             }
           ] =
             Report.items(report)
  end

  test "each call's reason sits by its changes and the turn's latest needs is kept", %{
    scope: scope,
    goal: goal,
    task: task
  } do
    ops(scope, goal, task, [add("intent", "prose", %{"text" => "a"})], %{
      "reason" => "Q3 → intent written",
      "needs" => "first"
    })

    ops(scope, goal, task, [add("intent", "prose", %{"text" => "b"})], %{"needs" => "confirm R1"})
    Workspaces.set_state(scope, :idle)

    {[report], _} = Planning.list_reports(goal, task)
    assert [%{"reasons" => ["Q3 → intent written"]}, %{"reasons" => []}] = Report.items(report)
    assert report.needs == "confirm R1"
  end

  test "item changes in a list widget are named by id", %{scope: scope, goal: goal, task: task} do
    {:ok, data} =
      Jarvis.Planning.Catalog.validate("examples", Jarvis.Planning.Catalog.example("examples"))

    widget = widget!(scope, goal, task, "examples", "examples", data)

    rows =
      data["rows"] |> List.delete_at(0) |> List.update_at(0, &%{&1 | "expected" => "changed"})

    rows = rows ++ [%{"id" => "r4", "values" => ["team", "9"], "expected" => "allowed"}]

    ops(scope, goal, task, [
      %{"op" => "update", "id" => widget.id, "data" => %{data | "rows" => rows}}
    ])

    Workspaces.set_state(scope, :idle)

    {[report], _} = Planning.list_reports(goal, task)
    [entry] = Report.items(report)

    assert Jarvis.Planning.Catalog.item_diff("examples", entry["before"], entry["after"]) == [
             {"rows", ["r4"], ["r1"], ["r2"]}
           ]
  end

  test "a turn that changed nothing on the board leaves no report", %{
    scope: scope,
    goal: goal,
    task: task
  } do
    {:ok, _} = Planning.add_comment(scope, goal, task, %{"body" => "only talking"})
    Workspaces.set_state(scope, :idle)
    assert Planning.list_reports(goal, task) == {[], []}
  end

  test "two sessions changing one task each get their own report", %{
    scope: scope,
    goal: goal,
    task: task
  } do
    other = scope.worktree.path |> agent_scope!() |> Workspaces.set_state(:working)
    ops(scope, goal, task, [add("intent", "prose", %{"text" => "a"})])
    ops(other, goal, task, [add("intent", "prose", %{"text" => "b"})])
    Workspaces.set_state(scope, :idle)
    Workspaces.set_state(other, :idle)

    {reports, _} = Planning.list_reports(goal, task)

    assert reports |> Enum.map(& &1.agent_session_id) |> Enum.sort() ==
             Enum.sort([scope.agent_session.id, other.agent_session.id])
  end

  test "reading a report moves it to the history", %{scope: scope, goal: goal, task: task} do
    ops(scope, goal, task, [add("intent", "prose", %{"text" => "a"})])
    Workspaces.set_state(scope, :idle)
    {[report], []} = Planning.list_reports(goal, task)

    {:ok, _} = Planning.read_report(human_scope(scope), report.id)
    assert {[], [%{id: id}]} = Planning.list_reports(goal, task)
    assert id == report.id
  end

  test "a goal's report shows its widgets and the tasks the turn created", %{
    scope: scope,
    goal: goal
  } do
    ops(scope, goal, nil, [add("intent", "prose", %{"text" => "why"})])
    {:ok, _} = Planning.create_task(scope, goal, %{"title" => "Second", "reason" => "split"})
    Workspaces.set_state(scope, :idle)

    # The newest; the setup's task was created in an earlier turn.
    {[report | _], []} = Planning.list_reports(goal, nil)

    assert [
             %{"action" => "added"},
             %{"action" => "task_created", "title" => "Second", "reasons" => ["split"]}
           ] =
             Report.items(report)
  end

  test "the human's own changes make no report", %{scope: scope, goal: goal, task: task} do
    widget!(scope, goal, task, "intent", "prose", %{"text" => "set up by the human"})
    Workspaces.set_state(scope, :idle)
    assert Planning.list_reports(goal, task) == {[], []}
  end
end
