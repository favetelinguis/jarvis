defmodule JarvisWeb.TranscriptLiveTest do
  use JarvisWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jarvis.Fixtures

  alias Jarvis.Transcripts

  setup do
    dir =
      Path.join([
        System.tmp_dir!(),
        "jarvis-test-transcripts",
        "live#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    path = Path.join(dir, "s.jsonl")

    File.write!(path, """
    {"type":"message","message":{"role":"user","content":"hello"}}
    {"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","name":"bash","arguments":{}}]}}
    """)

    sync = fn ->
      Transcripts.sync(%{
        "harness" => "pi",
        "session_id" => "s",
        "transcript_path" => path,
        "cwd" => git_repo!()
      })
    end

    {:ok, transcript, 2} = sync.()
    %{transcript: transcript, path: path}
  end

  test "shows the conversation, tool calls on demand, and new lines live", %{
    conn: conn,
    transcript: t,
    path: path
  } do
    {:ok, view, _html} = live(conn, ~p"/transcripts/#{t.id}")
    assert has_element?(view, "#entry-0", "hello")
    refute has_element?(view, "#entry-1")

    view |> element("#toggle-tools") |> render_click()
    assert has_element?(view, "#entry-1", "bash")

    File.write!(path, ~s({"type":"message","message":{"role":"user","content":"more"}}\n), [
      :append
    ])

    {:ok, _, 1} =
      Transcripts.sync(%{
        "harness" => "pi",
        "session_id" => "s",
        "transcript_path" => path,
        "cwd" => t.cwd
      })

    assert has_element?(view, "#entry-2", "more")
  end

  test "restores the session file and shows how to resume it", %{
    conn: conn,
    transcript: t,
    path: path
  } do
    File.rm!(path)
    {:ok, view, _html} = live(conn, ~p"/transcripts/#{t.id}")

    view |> element("#restore") |> render_click()
    assert has_element?(view, "#resume-command", "pi --session")
    assert File.exists?(path)
  end
end
