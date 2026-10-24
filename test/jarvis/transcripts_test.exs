defmodule Jarvis.TranscriptsTest do
  use Jarvis.DataCase, async: true

  import Jarvis.Fixtures

  alias Jarvis.Transcripts

  @root Path.join(System.tmp_dir!(), "jarvis-test-transcripts")

  setup do
    dir = Path.join(@root, "t#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{path: Path.join(dir, "session.jsonl"), cwd: git_repo!()}
  end

  defp sync(harness, path, cwd, session \\ "s1") do
    Transcripts.sync(%{
      "harness" => harness,
      "session_id" => session,
      "transcript_path" => path,
      "cwd" => cwd
    })
  end

  defp pi_user(text),
    do:
      ~s({"type":"message","timestamp":"2026-01-01T10:00:00.123Z","message":{"role":"user","content":"#{text}"}}\n)

  describe "sync/1" do
    test "reads complete lines once, then only what was appended", %{path: path, cwd: cwd} do
      File.write!(path, ~s({"type":"session","id":"s1"}\n) <> pi_user("hello"))

      assert {:ok, transcript, 2} = sync("pi", path, cwd)
      assert transcript.title == "hello"
      assert {:ok, _, 0} = sync("pi", path, cwd)

      File.write!(path, pi_user("again"), [:append])
      assert {:ok, %{line_count: 3}, 1} = sync("pi", path, cwd)
    end

    test "leaves a line without its newline for the next sync", %{path: path, cwd: cwd} do
      File.write!(path, pi_user("one") <> ~s({"type":"mess))
      assert {:ok, _, 1} = sync("pi", path, cwd)

      File.write!(path, ~s(age","message":{"role":"user","content":"two"}}\n), [:append])
      assert {:ok, transcript, 1} = sync("pi", path, cwd)

      assert [%{text: "one"}, %{text: "two"}] = Transcripts.list_entries(transcript)
    end

    test "reads a rewritten file again from the start", %{path: path, cwd: cwd} do
      File.write!(path, pi_user("old") <> pi_user("lines"))
      {:ok, _, 2} = sync("pi", path, cwd)

      File.write!(path, pi_user("new"))
      assert {:ok, transcript, 1} = sync("pi", path, cwd)
      assert [%{text: "new"}] = Transcripts.list_entries(transcript)
    end

    test "waits for a file that does not exist yet", %{path: path, cwd: cwd} do
      assert {:ok, %{line_count: 0}, 0} = sync("pi", path, cwd)
    end

    test "refuses files outside the transcript roots and unknown harnesses", %{
      path: path,
      cwd: cwd
    } do
      assert {:error, :path_not_allowed} = sync("pi", "/etc/passwd", cwd)
      assert {:error, :path_not_allowed} = sync("pi", Path.join(@root, "../escape.jsonl"), cwd)
      assert {:error, :path_not_allowed} = sync("pi", String.replace(path, ".jsonl", ".txt"), cwd)
      assert {:error, :invalid_harness} = sync("claude", path, cwd)
    end

    test "files the transcript under the project and worktree of its cwd", %{path: path, cwd: cwd} do
      File.write!(path, pi_user("hi"))
      {:ok, transcript, _} = sync("pi", path, cwd)

      scope = agent_scope!(cwd)
      assert transcript.project_id == scope.project.id
      assert transcript.worktree_id == scope.worktree.id
      assert [%{id: id}] = Transcripts.list_transcripts(scope.project.id)
      assert id == transcript.id
    end
  end

  describe "reading pi sessions" do
    test "shows conversation and tool use, hides prompt loadout", %{path: path, cwd: cwd} do
      File.write!(path, """
      {"type":"session","version":3,"id":"s1","cwd":"/x"}
      {"type":"message","id":"a","message":{"role":"system","content":"","sections":{}}}
      {"type":"message","id":"b","message":{"role":"user","content":[{"type":"text","text":"fix it"}]}}
      {"type":"message","id":"c","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hm"},{"type":"toolCall","id":"1","name":"bash","arguments":{"command":"ls"}}]}}
      {"type":"message","id":"d","message":{"role":"toolResult","toolName":"bash","content":[{"type":"text","text":"a.ex"}]}}
      {"type":"message","id":"e","message":{"role":"assistant","content":[{"type":"text","text":"Fixed."}]}}
      {"type":"session_info","id":"f","name":"Fix the bug"}
      """)

      {:ok, transcript, 7} = sync("pi", path, cwd)

      assert transcript.title == "Fix the bug"

      assert [
               %{role: :user, text: "fix it"},
               %{role: :tool_call, text: ~s(→ bash {"command":"ls"})},
               %{role: :tool_result, text: "bash: a.ex"},
               %{role: :assistant, text: "Fixed."}
             ] = Transcripts.list_entries(transcript)
    end
  end

  describe "reading Codex rollouts" do
    test "shows the user's words, not injected context", %{path: path, cwd: cwd} do
      File.write!(path, """
      {"timestamp":"2026-01-01T10:00:00.000Z","type":"session_meta","payload":{"id":"c1"}}
      {"timestamp":"2026-01-01T10:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md ..."}]}}
      {"timestamp":"2026-01-01T10:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"add a test"}}
      {"timestamp":"2026-01-01T10:00:02.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"ls\\"}"}}
      {"timestamp":"2026-01-01T10:00:03.000Z","type":"response_item","payload":{"type":"function_call_output","output":"a.ex"}}
      {"timestamp":"2026-01-01T10:00:04.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done."}]}}
      """)

      {:ok, transcript, 6} = sync("codex", path, cwd, "c1")

      assert transcript.title == "add a test"

      assert [
               %{role: :user, text: "add a test"},
               %{role: :tool_call, text: ~s(→ exec_command {"cmd":"ls"})},
               %{role: :tool_result, text: "a.ex"},
               %{role: :assistant, text: "Done."}
             ] = Transcripts.list_entries(transcript)
    end
  end

  describe "restore/1" do
    setup %{path: path, cwd: cwd} do
      # Unicode and odd spacing must survive byte for byte.
      original =
        ~s({"type":"session","id":"s1"}\n{ "type" : "message", "message":{"role":"user","content":"héllo ✓"}}\n)

      File.write!(path, original)
      {:ok, transcript, 2} = sync("pi", path, cwd)
      %{original: original, transcript: transcript}
    end

    test "writes a missing file back byte for byte", %{
      path: path,
      original: original,
      transcript: t
    } do
      File.rm!(path)

      assert {:ok, %{status: :written, path: ^path, command: command}} = Transcripts.restore(t)
      assert File.read!(path) == original
      assert command =~ "pi --session '#{path}'"
    end

    test "leaves a file that already holds the transcript alone", %{path: path, transcript: t} do
      File.write!(path, pi_user("not synced yet"), [:append])
      before = File.read!(path)

      assert {:ok, %{status: :unchanged}} = Transcripts.restore(t)
      assert File.read!(path) == before
    end

    test "moves a different file aside before writing", %{
      path: path,
      original: original,
      transcript: t
    } do
      File.write!(path, "something else\n")

      assert {:ok, %{status: :replaced, backup: backup}} = Transcripts.restore(t)
      assert File.read!(path) == original
      assert File.read!(backup) == "something else\n"
    end

    test "resumes Codex sessions by id", %{path: path, cwd: cwd} do
      File.write!(path, ~s({"type":"session_meta","payload":{}}\n))
      {:ok, t, 1} = sync("codex", path, cwd, "019f-abc")

      assert {:ok, %{command: command}} = Transcripts.restore(t)
      assert command =~ "codex resume 019f-abc"
    end
  end
end
