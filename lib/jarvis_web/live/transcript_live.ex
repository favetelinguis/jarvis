defmodule JarvisWeb.TranscriptLive do
  @moduledoc """
  A mirrored agent session, read in harness-neutral form, with a one-click
  restore that writes the session file back so the harness can resume it.
  """
  use JarvisWeb, :live_view

  alias Jarvis.{Transcripts, Workspaces}

  @conversation [:user, :assistant, :system]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    transcript = Transcripts.get_transcript!(id)
    if connected?(socket), do: Workspaces.subscribe(transcript.project_id)

    {:ok,
     socket
     |> assign(:transcript, transcript)
     |> assign(:page_title, transcript.title || "Transcript")
     |> assign(:show_tools, false)
     |> assign(:restored, nil)
     |> reset_entries()}
  end

  @impl true
  def handle_info({:jarvis, :changed}, socket) do
    transcript = Transcripts.get_transcript!(socket.assigns.transcript.id)

    entries =
      Transcripts.list_entries(transcript, roles: roles(socket), after: socket.assigns.last_seq)

    {:noreply,
     socket
     |> assign(:transcript, transcript)
     |> stream_entries(entries)}
  end

  @impl true
  def handle_event("toggle_tools", _params, socket) do
    {:noreply, socket |> assign(:show_tools, not socket.assigns.show_tools) |> reset_entries()}
  end

  def handle_event("restore", _params, socket) do
    case Transcripts.restore(socket.assigns.transcript) do
      {:ok, result} ->
        {:noreply, assign(socket, :restored, result)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Restore failed: #{inspect(reason)}")}
    end
  end

  defp roles(socket),
    do:
      if(socket.assigns.show_tools,
        do: @conversation ++ [:tool_call, :tool_result],
        else: @conversation
      )

  defp reset_entries(socket) do
    entries = Transcripts.list_entries(socket.assigns.transcript, roles: roles(socket))

    socket
    |> assign(:last_seq, -1)
    |> stream(:entries, [], reset: true, dom_id: &"entry-#{&1.seq}")
    |> stream_entries(entries)
  end

  defp stream_entries(socket, entries) do
    last_seq = entries |> List.last(%{seq: socket.assigns.last_seq}) |> Map.fetch!(:seq)
    socket |> assign(:last_seq, last_seq) |> stream(:entries, entries, dom_id: &"entry-#{&1.seq}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      crumbs={[
        {@transcript.project.name, ~p"/projects/#{@transcript.project}"},
        {"Transcript", ~p"/transcripts/#{@transcript.id}"}
      ]}
    >
      <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <.harness_badge harness={@transcript.harness} />
            <span class="font-mono text-xs text-base-content/40">{@transcript.external_id}</span>
          </div>
          <h1 class="mt-2 text-xl font-semibold tracking-tight">
            {@transcript.title || "Untitled session"}
          </h1>
          <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-base-content/50">
            <.worktree_chip worktree={@transcript.worktree} />
            <span>{@transcript.line_count} lines mirrored</span>
            <span class="truncate font-mono" title={@transcript.path}>{@transcript.path}</span>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <button
            id="toggle-tools"
            type="button"
            phx-click="toggle_tools"
            class="rounded-lg border border-base-300 px-3 py-1.5 text-sm transition hover:bg-base-200"
          >
            {if @show_tools, do: "Hide tool calls", else: "Show tool calls"}
          </button>
          <button
            id="restore"
            type="button"
            phx-click="restore"
            class="rounded-lg bg-base-content px-3 py-1.5 text-sm font-medium text-base-100 transition hover:opacity-85 active:scale-[0.98] phx-click-loading:opacity-50"
          >
            <.icon name="hero-arrow-uturn-left-mini" class="size-4" /> Restore session
          </button>
        </div>
      </header>

      <div
        :if={@restored}
        id="restore-result"
        class="mb-6 rounded-2xl border border-emerald-500/30 bg-emerald-500/5 p-4 text-sm"
      >
        <p class="font-medium">
          <%= case @restored.status do %>
            <% :written -> %>
              Session file written back from the database.
            <% :unchanged -> %>
              The session file on disk already holds this transcript.
            <% :replaced -> %>
              The session file on disk differed; it was moved to <code>{@restored.backup}</code>
              and replaced.
          <% end %>
          Resume it with:
        </p>
        <div class="mt-2 flex items-center gap-2">
          <code
            id="resume-command"
            class="min-w-0 flex-1 overflow-x-auto whitespace-nowrap rounded-lg bg-base-100 px-3 py-2 font-mono text-xs"
          >
            {@restored.command}
          </code>
          <button
            id="copy-command"
            type="button"
            phx-hook=".Copy"
            data-target="resume-command"
            class="rounded-lg border border-base-300 bg-base-100 px-2.5 py-2 text-xs transition hover:bg-base-200"
          >
            Copy
          </button>
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".Copy">
          export default {
            mounted() {
              this.el.addEventListener("click", () => {
                const text = document.getElementById(this.el.dataset.target).innerText.trim()
                navigator.clipboard.writeText(text).then(() => {
                  this.el.innerText = "Copied"
                  setTimeout(() => (this.el.innerText = "Copy"), 1500)
                })
              })
            }
          }
        </script>
      </div>

      <ol id="entries" phx-update="stream" class="mx-auto max-w-4xl space-y-3">
        <li id="entries-empty" class="hidden text-sm text-base-content/50 only:block">
          Nothing to show yet.
        </li>
        <li :for={{dom_id, entry} <- @streams.entries} id={dom_id} class={entry_class(entry.role)}>
          <div class="mb-1 flex items-center gap-2 text-[11px] uppercase tracking-wider opacity-50">
            <span>{entry_label(entry.role)}</span>
            <span :if={entry.at} class="normal-case tracking-normal">
              {Calendar.strftime(entry.at, "%H:%M:%S")}
            </span>
          </div>
          <%= if entry.role in [:tool_call, :tool_result] do %>
            <pre class="max-h-72 overflow-auto whitespace-pre-wrap break-words font-mono text-xs text-base-content/70">{entry.text}</pre>
          <% else %>
            <.markdown text={entry.text} class="text-sm" />
          <% end %>
        </li>
      </ol>
    </Layouts.app>
    """
  end

  defp entry_label(:user), do: "You"
  defp entry_label(:assistant), do: "Agent"
  defp entry_label(:tool_call), do: "Tool call"
  defp entry_label(:tool_result), do: "Tool result"
  defp entry_label(:system), do: "System"

  defp entry_class(:user),
    do:
      "ml-auto max-w-[85%] rounded-2xl rounded-br-md bg-base-content/90 px-4 py-3 text-base-100 [&_.md]:text-base-100"

  defp entry_class(:assistant),
    do:
      "max-w-[92%] rounded-2xl rounded-bl-md border border-base-300 bg-base-100 px-4 py-3 shadow-sm"

  defp entry_class(:system),
    do: "rounded-xl border border-dashed border-base-300 px-4 py-3 text-base-content/70"

  defp entry_class(_tool), do: "rounded-xl bg-base-200/60 px-4 py-2"
end
