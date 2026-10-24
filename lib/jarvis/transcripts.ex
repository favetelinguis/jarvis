defmodule Jarvis.Transcripts do
  @moduledoc """
  Mirrors agent session files (pi sessions, Codex rollouts) into the database
  and writes them back, so a session can be resumed from Jarvis exactly as the
  harness's own resume would.

  Harness hooks only report where a session file is (`sync/1`); Jarvis reads
  the file itself, incrementally, so each hook stays a one-line notification.
  """

  import Ecto.Query

  alias Jarvis.Repo
  alias Jarvis.Transcripts.{Harness, Line, Transcript}
  alias Jarvis.Workspaces

  @insert_batch 1_000

  ## Sync

  @doc """
  Reads any new complete lines of a session file into its transcript.

  `params` carries `harness` (`"pi"` or `"codex"`), `session_id`,
  `transcript_path`, and `cwd`, the shape Codex hooks receive on stdin. The
  path must be a `.jsonl` file under one of the configured transcript roots. A
  file that was rewritten rather than appended to is read again in full; a
  trailing line without its newline waits for the next sync.

  Returns the transcript and the number of lines added.
  """
  def sync(params) do
    with {:ok, harness} <- harness(params["harness"]),
         {:ok, session_id} <- session_id(params["session_id"]),
         {:ok, path} <- allowed_path(params["transcript_path"]),
         {:ok, {project, worktree}} <- Workspaces.locate(params["cwd"]) do
      result =
        Repo.transact(fn ->
          transcript =
            lock_or_create!(%Transcript{
              harness: harness,
              external_id: session_id,
              path: path,
              cwd: params["cwd"],
              project_id: project.id,
              worktree_id: worktree.id
            })

          read_new_lines(transcript)
        end)

      with {:ok, {transcript, added}} <- result do
        if added > 0, do: Workspaces.broadcast_change(project.id)
        {:ok, transcript, added}
      end
    end
  end

  defp harness("pi"), do: {:ok, :pi}
  defp harness("codex"), do: {:ok, :codex}
  defp harness(_), do: {:error, :invalid_harness}

  defp session_id(id) when is_binary(id) and byte_size(id) in 1..255, do: {:ok, id}
  defp session_id(_), do: {:error, :invalid_session_id}

  @doc "Whether Jarvis may read and write `path`: a `.jsonl` file under a configured root."
  def allowed_path(path) when is_binary(path) do
    expanded = Path.expand(path)

    allowed? =
      Path.type(path) == :absolute and Path.extname(expanded) == ".jsonl" and
        Enum.any?(roots(), &String.starts_with?(expanded, Path.expand(&1) <> "/"))

    if allowed?, do: {:ok, expanded}, else: {:error, :path_not_allowed}
  end

  def allowed_path(_), do: {:error, :path_not_allowed}

  defp roots, do: Application.fetch_env!(:jarvis, :transcript_roots)

  defp lock_or_create!(%Transcript{} = new) do
    Repo.insert!(new,
      on_conflict: {:replace, [:path, :cwd, :project_id, :worktree_id]},
      conflict_target: [:harness, :external_id]
    )

    Repo.one!(
      from t in Transcript,
        where: t.harness == ^new.harness and t.external_id == ^new.external_id,
        lock: "FOR UPDATE"
    )
  end

  defp read_new_lines(transcript) do
    case File.open(transcript.path, [:read, :binary, :raw]) do
      {:ok, file} ->
        try do
          transcript =
            if unchanged_prefix?(file, transcript), do: transcript, else: reset!(transcript)

          {:ok, append!(file, transcript)}
        after
          File.close(file)
        end

      # pi creates its session file only once the first reply is written.
      {:error, :enoent} ->
        {:ok, {transcript, 0}}

      {:error, reason} ->
        {:error, {:unreadable, reason}}
    end
  end

  defp unchanged_prefix?(_file, %Transcript{line_count: 0}), do: true

  defp unchanged_prefix?(file, transcript) do
    length = transcript.byte_offset - transcript.last_line_offset

    case :file.pread(file, transcript.last_line_offset, length) do
      {:ok, bytes} when byte_size(bytes) == length -> hash(bytes) == transcript.last_line_hash
      _ -> false
    end
  end

  defp reset!(transcript) do
    Repo.delete_all(from l in Line, where: l.transcript_id == ^transcript.id)

    %{
      transcript
      | line_count: 0,
        byte_offset: 0,
        last_line_offset: 0,
        last_line_hash: nil,
        title: nil
    }
  end

  defp append!(file, transcript) do
    {:ok, size} = :file.position(file, :eof)

    {:ok, tail} =
      if size > transcript.byte_offset,
        do: :file.pread(file, transcript.byte_offset, size - transcript.byte_offset),
        else: {:ok, ""}

    # Each element is a complete line with its newline; the last element of
    # the split is whatever follows the last newline: incomplete, left unread.
    complete = tail |> :binary.split("\n", [:global]) |> Enum.drop(-1) |> Enum.map(&(&1 <> "\n"))
    harness = Harness.for(transcript.harness)

    {rows, last} =
      complete
      |> Enum.with_index(transcript.line_count)
      |> Enum.map_reduce({transcript.byte_offset, transcript.byte_offset, nil}, fn {bytes, seq},
                                                                                   {offset, _, _} ->
        entry = read_line(harness, bytes)

        row = %{
          transcript_id: transcript.id,
          seq: seq,
          line: bytes,
          role: entry.role,
          text: entry.text,
          at: entry.at
        }

        {{row, entry}, {offset + byte_size(bytes), offset, bytes}}
      end)

    rows
    |> Enum.map(&elem(&1, 0))
    |> Enum.chunk_every(@insert_batch)
    |> Enum.each(&Repo.insert_all(Line, &1))

    entries = Enum.map(rows, &elem(&1, 1))
    added = length(complete)

    transcript =
      if added == 0 do
        transcript
      else
        {byte_offset, last_line_offset, last_bytes} = last

        transcript
        |> Ecto.Changeset.change(
          line_count: transcript.line_count + added,
          byte_offset: byte_offset,
          last_line_offset: last_line_offset,
          last_line_hash: hash(last_bytes),
          title: title(transcript.title, entries),
          last_entry_at:
            entries
            |> Enum.map(& &1.at)
            |> Enum.reject(&is_nil/1)
            |> List.last(transcript.last_entry_at)
        )
        |> Repo.update!()
      end

    {transcript, added}
  end

  defp read_line(harness, bytes) do
    case Jason.decode(bytes) do
      {:ok, decoded} when is_map(decoded) -> harness.read(decoded)
      _ -> %{role: :meta, text: nil, at: nil}
    end
  end

  # An explicit name wins; otherwise the first thing the user said.
  defp title(current, entries) do
    named = entries |> Enum.map(&Map.get(&1, :title)) |> Enum.reject(&is_nil/1) |> List.last()

    cond do
      named ->
        named

      current ->
        current

      first = Enum.find(entries, &(&1.role == :user and &1.text not in [nil, ""])) ->
        first.text |> String.trim() |> String.slice(0, 120)

      true ->
        nil
    end
  end

  defp hash(bytes), do: :crypto.hash(:sha256, bytes)

  ## Restore

  @doc """
  Writes the transcript back to its original path, byte for byte, so the
  harness can resume it.

  A file already holding the transcript (or the transcript and more) is left
  alone. A file with other content is moved aside to `<path>.jarvis-backup-<unix time>`.
  Returns how the file was handled and the shell command that resumes the session.
  """
  def restore(%Transcript{} = transcript) do
    with {:ok, path} <- allowed_path(transcript.path) do
      content =
        Repo.all(
          from l in Line,
            where: l.transcript_id == ^transcript.id,
            order_by: l.seq,
            select: l.line
        )

      content = IO.iodata_to_binary(content)
      size = byte_size(content)

      outcome =
        case File.read(path) do
          {:ok, <<^content::binary-size(^size), _newer::binary>>} ->
            {:ok, :unchanged, nil}

          {:ok, _different} ->
            backup = "#{path}.jarvis-backup-#{System.os_time(:second)}"

            with :ok <- File.rename(path, backup), :ok <- File.write(path, content) do
              {:ok, :replaced, backup}
            end

          {:error, :enoent} ->
            with :ok <- File.mkdir_p(Path.dirname(path)), :ok <- File.write(path, content) do
              {:ok, :written, nil}
            end

          {:error, reason} ->
            {:error, reason}
        end

      with {:ok, status, backup} <- outcome do
        {:ok,
         %{
           status: status,
           path: path,
           backup: backup,
           command: Harness.for(transcript.harness).resume_command(transcript)
         }}
      end
    end
  end

  ## Queries

  @doc "The project's transcripts, most recently active first, with their worktrees."
  def list_transcripts(project_id, limit \\ 50) do
    from(t in Transcript,
      where: t.project_id == ^project_id and t.line_count > 0,
      order_by: [desc_nulls_last: t.last_entry_at],
      limit: ^limit,
      preload: :worktree
    )
    |> Repo.all()
  end

  def get_transcript!(id), do: Transcript |> Repo.get!(id) |> Repo.preload([:project, :worktree])

  @doc "Fetches the transcript of a harness session by the harness's session id."
  def fetch_by_session(harness, external_id) do
    case Repo.get_by(Transcript, harness: harness, external_id: external_id) do
      nil -> {:error, :not_found}
      transcript -> {:ok, transcript}
    end
  end

  @doc """
  The readable lines of a transcript in order, without their raw bytes.

  Options: `:roles` to show (default: all but `:meta`), and `:after`, a
  sequence number to continue after.
  """
  def list_entries(%Transcript{id: id}, opts \\ []) do
    roles = Keyword.get(opts, :roles, Line.roles() -- [:meta])
    after_seq = Keyword.get(opts, :after, -1)

    from(l in Line,
      where: l.transcript_id == ^id and l.role in ^roles and l.seq > ^after_seq,
      order_by: l.seq,
      select: %{seq: l.seq, role: l.role, text: l.text, at: l.at}
    )
    |> Repo.all()
  end
end
