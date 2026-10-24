defmodule JarvisWeb.Api.TranscriptControllerTest do
  use JarvisWeb.ConnCase, async: true

  import Jarvis.Fixtures

  @root Path.join(System.tmp_dir!(), "jarvis-test-transcripts")

  setup %{conn: conn} do
    repo = git_repo!()
    dir = Path.join(@root, "api#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      repo: repo,
      path: Path.join(dir, "rollout.jsonl")
    }
  end

  test "a Codex hook payload syncs as is, and the session restores", %{
    conn: conn,
    repo: repo,
    path: path
  } do
    File.write!(path, ~s({"type":"event_msg","payload":{"type":"user_message","message":"hi"}}\n))

    hook_input = %{
      "session_id" => "019f-1",
      "transcript_path" => path,
      "cwd" => repo,
      "hook_event_name" => "Stop",
      "model" => "gpt"
    }

    assert %{"id" => id, "added" => 1} =
             conn
             |> post(~p"/api/transcripts/sync?harness=codex", hook_input)
             |> json_response(200)

    agent =
      conn
      |> put_req_header("x-jarvis-cwd", URI.encode(repo))
      |> put_req_header("x-jarvis-session", "pi-1")

    assert %{"transcripts" => [%{"id" => ^id, "harness" => "codex", "title" => "hi"}]} =
             agent |> get(~p"/api/transcripts") |> json_response(200)

    File.rm!(path)

    assert %{"status" => "written", "command" => command} =
             agent |> post(~p"/api/transcripts/#{id}/restore") |> json_response(200)

    assert command =~ "codex resume 019f-1"
    assert File.exists?(path)
  end

  test "refuses to restore another project's transcript", %{conn: conn, repo: repo, path: path} do
    File.write!(path, "{}\n")

    %{"id" => id} =
      conn
      |> post(~p"/api/transcripts/sync?harness=pi", %{
        "session_id" => "p",
        "transcript_path" => path,
        "cwd" => repo
      })
      |> json_response(200)

    stranger =
      conn
      |> put_req_header("x-jarvis-cwd", URI.encode(git_repo!()))
      |> put_req_header("x-jarvis-session", "other")

    assert stranger |> post(~p"/api/transcripts/#{id}/restore") |> json_response(404)
  end

  test "rejects paths outside the transcript roots", %{conn: conn, repo: repo} do
    payload = %{"session_id" => "x", "transcript_path" => "/etc/passwd", "cwd" => repo}

    assert %{"error" => "path_not_allowed"} =
             conn |> post(~p"/api/transcripts/sync?harness=pi", payload) |> json_response(422)
  end
end
