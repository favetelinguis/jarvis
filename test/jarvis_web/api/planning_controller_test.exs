defmodule JarvisWeb.Api.PlanningControllerTest do
  use JarvisWeb.ConnCase, async: true

  import Jarvis.Fixtures

  setup %{conn: conn} do
    repo = git_repo!()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-jarvis-cwd", URI.encode(repo))
      |> put_req_header("x-jarvis-session", "api-session")
      |> put_req_header("x-jarvis-session-name", URI.encode("design run"))

    %{conn: conn, repo: repo}
  end

  test "requires the identity headers", %{conn: conn} do
    conn = conn |> delete_req_header("x-jarvis-cwd") |> get(~p"/api/overview")
    assert %{"details" => %{"cwd" => _}} = json_response(conn, 400)
  end

  test "creates a goal and a typed task, writes widgets, and moves the task", %{conn: conn} do
    created = conn |> post(~p"/api/goals", %{title: "Board"}) |> json_response(201)
    assert %{"goal" => 1, "url" => url, "text" => text} = created
    assert url =~ ~r"/projects/\d+/goals/1$"
    assert text =~ "# Goal 1: Board"
    assert text =~ "## Intent (`intent`)"

    task =
      conn
      |> post(~p"/api/goals/1/tasks", %{title: "Show", type: "research", claim: true})
      |> json_response(201)

    assert %{"goal" => 1, "task" => 1} = task
    assert task["text"] =~ "**Worktree:**"
    assert task["text"] =~ "**Type:** Research"
    assert task["text"] =~ "**Step:** Question"

    ops = [
      %{op: "add", section: "question", kind: "prose", data: %{text: "Why is the sky blue?"}}
    ]

    written = conn |> post(~p"/api/goals/1/tasks/1/widgets", %{ops: ops}) |> json_response(200)
    assert written["text"] =~ "· prose"
    assert written["text"] =~ "Why is the sky blue?"

    moved =
      conn
      |> patch(~p"/api/goals/1/tasks/1", %{transition: "approve question"})
      |> json_response(422)

    assert %{"details" => %{"transition" => ["This transition is the human's decision"]}} = moved

    jumped =
      conn
      |> patch(~p"/api/goals/1/tasks/1", %{force_step: "investigation"})
      |> json_response(200)

    assert jumped["text"] =~ "**Step:** Investigation"

    overview = conn |> get(~p"/api/overview") |> json_response(200)
    assert overview["text"] =~ "Task 1.1: Show [Research · Investigation]"
    assert overview["text"] =~ "design run"
  end

  test "rejects invalid widgets with every reason and changes nothing", %{conn: conn} do
    conn |> post(~p"/api/goals", %{title: "Board"}) |> json_response(201)
    ops = [%{op: "add", section: "intent", kind: "callout", data: %{tone: "loud"}}]

    assert %{"details" => %{"widgets" => messages}} =
             conn |> post(~p"/api/goals/1/widgets", %{ops: ops}) |> json_response(422)

    assert Enum.any?(messages, &(&1 =~ "tone: must be one of info, warning, risk"))
    assert Enum.any?(messages, &(&1 =~ "title: required"))
    assert %{"text" => text} = conn |> get(~p"/api/goals/1") |> json_response(200)
    assert text =~ "_Nothing yet._"
  end

  test "serves the widget catalog", %{conn: conn} do
    assert %{"text" => text} = conn |> get(~p"/api/catalog") |> json_response(200)
    assert text =~ "### requirement — Requirement card"
  end

  test "wakes the listening session with anchored comments", %{conn: conn, repo: repo} do
    conn |> post(~p"/api/goals", %{title: "Board"}) |> json_response(201)
    conn |> post(~p"/api/goals/1/tasks", %{title: "Show", claim: true}) |> json_response(201)
    ops = [%{op: "add", section: "intent", kind: "prose", data: %{text: "hello"}}]
    conn |> post(~p"/api/goals/1/tasks/1/widgets", %{ops: ops}) |> json_response(200)
    assert %{"count" => 0} = conn |> post(~p"/api/wake") |> json_response(200)

    scope = agent_scope!(repo)
    {:ok, task} = Jarvis.Planning.fetch_task(scope, 1, 1)
    [widget] = Jarvis.Planning.list_widgets(task.goal, task)
    attrs = %{"body" => "Shorter please", "widget" => widget.id}
    {:ok, asked} = Jarvis.Planning.add_comment(human_scope(scope), task.goal, task, attrs)

    assert %{"count" => 1, "text" => text} = conn |> post(~p"/api/wake") |> json_response(200)
    assert text =~ "Shorter please"
    assert %{"count" => 0} = conn |> post(~p"/api/wake") |> json_response(200)

    reply =
      conn
      |> post(~p"/api/goals/1/comments", %{task: 1, body: "Done", reply_to: asked.id})
      |> json_response(200)

    assert reply["text"] =~ "**agent**"
  end

  test "reports unknown goals and invalid fields", %{conn: conn} do
    assert %{"error" => _} = conn |> get(~p"/api/goals/7") |> json_response(404)
    assert %{"error" => _} = conn |> get(~p"/api/goals/x") |> json_response(404)

    assert %{"details" => %{"title" => _}} =
             conn |> post(~p"/api/goals", %{}) |> json_response(422)
  end

  test "delivers human comments through the inbox", %{conn: conn, repo: repo} do
    conn |> post(~p"/api/goals", %{title: "Board"}) |> json_response(201)
    assert %{"count" => 0} = conn |> post(~p"/api/inbox") |> json_response(200)

    scope = agent_scope!(repo)
    {:ok, goal} = Jarvis.Planning.fetch_goal(scope, 1)

    {:ok, _} =
      Jarvis.Planning.add_comment(human_scope(scope), goal, nil, %{"body" => "Keep it small"})

    assert %{"count" => 1, "text" => text} = conn |> post(~p"/api/inbox") |> json_response(200)
    assert text =~ "Keep it small"
    assert %{"count" => 0} = conn |> post(~p"/api/inbox") |> json_response(200)
  end

  test "records the session state", %{conn: conn} do
    assert conn |> put(~p"/api/session", %{state: "working"}) |> json_response(200)
    assert conn |> put(~p"/api/session", %{state: "asleep"}) |> json_response(422)
  end
end
