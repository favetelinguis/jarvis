defmodule JarvisWeb.Api.TranscriptController do
  @moduledoc """
  Session mirroring for harness hooks, and restoring for agents.

  `sync` takes the JSON a Codex hook receives on stdin as is (plus `harness`,
  usually as a query parameter), so a hook can pipe it straight to curl.
  """
  use JarvisWeb, :controller

  alias Jarvis.Transcripts

  action_fallback JarvisWeb.Api.FallbackController

  def sync(conn, params) do
    case Transcripts.sync(params) do
      {:ok, transcript, added} ->
        json(conn, %{id: transcript.id, lines: transcript.line_count, added: added})

      {:error, reason} when is_atom(reason) ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: reason})

      {:error, {:unreadable, reason}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "unreadable", reason: inspect(reason)})
    end
  end

  def index(conn, _params) do
    project = conn.assigns.current_scope.project

    transcripts =
      for t <- Transcripts.list_transcripts(project.id) do
        %{
          id: t.id,
          harness: t.harness,
          session_id: t.external_id,
          title: t.title,
          lines: t.line_count,
          worktree: t.worktree && t.worktree.name,
          branch: t.worktree && t.worktree.branch,
          last_entry_at: t.last_entry_at,
          path: t.path
        }
      end

    json(conn, %{transcripts: transcripts})
  end

  def restore(conn, %{"id" => id}) do
    project = conn.assigns.current_scope.project

    with {:ok, transcript} <- fetch_in_project(id, project.id),
         {:ok, result} <- Transcripts.restore(transcript) do
      json(conn, result)
    else
      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  defp fetch_in_project(id, project_id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %{project_id: ^project_id} = transcript <- Jarvis.Repo.get(Transcripts.Transcript, id) do
      {:ok, transcript}
    else
      _ -> {:error, :not_found}
    end
  end
end
