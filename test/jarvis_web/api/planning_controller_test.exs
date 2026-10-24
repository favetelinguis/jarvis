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

  test "creates, updates, and reads a goal and its task", %{conn: conn} do
    created =
      conn |> post(~p"/api/goals", %{title: "Board", intent: "See agents"}) |> json_response(201)

    assert %{"goal" => 1, "url" => url, "text" => text} = created
    assert url =~ ~r"/projects/\d+/goals/1$"
    assert text =~ "# Goal 1: Board"

    task =
      conn |> post(~p"/api/goals/1/tasks", %{title: "Show", claim: true}) |> json_response(201)

    assert %{"goal" => 1, "task" => 1} = task
    assert task["text"] =~ "**Worktree:**"

    updated = conn |> patch(~p"/api/goals/1/tasks/1", %{status: "ready"}) |> json_response(200)
    assert updated["text"] =~ "[ready]"

    overview = conn |> get(~p"/api/overview") |> json_response(200)
    assert overview["text"] =~ "Task 1.1: Show [ready]"
    assert overview["text"] =~ "design run"
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
