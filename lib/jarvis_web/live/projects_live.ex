defmodule JarvisWeb.ProjectsLive do
  @moduledoc "Every project agents have registered, with live task counts and sessions."
  use JarvisWeb, :live_view

  alias Jarvis.Workspaces

  @tick_ms 20_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Workspaces.subscribe(:all)
      :timer.send_interval(@tick_ms, :tick)
    end

    {:ok, socket |> assign(:page_title, "Projects") |> load()}
  end

  @impl true
  def handle_info({:jarvis, :changed}, socket), do: {:noreply, load(socket)}
  def handle_info(:tick, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    projects = Workspaces.list_projects()

    socket
    |> assign(:now, DateTime.utc_now())
    |> assign(:empty?, projects == [])
    |> stream(:projects, projects, reset: true, dom_id: &"project-#{&1.project.id}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mb-8">
        <h1 class="text-2xl font-semibold tracking-tight">Projects</h1>
        <p class="mt-1 text-sm text-base-content/60">
          Every repository a pi agent has worked in. Worktrees of one repository share a project.
        </p>
      </div>

      <div
        :if={@empty?}
        id="no-projects"
        class="rounded-2xl border border-dashed border-base-300 p-10 text-center"
      >
        <.icon name="hero-sparkles" class="size-8 text-base-content/30" />
        <p class="mt-3 font-medium">No projects yet</p>
        <p class="mt-1 text-sm text-base-content/60">
          Start pi with the Jarvis extension in any git repository and run <code class="rounded bg-base-200 px-1">/specify</code>.
        </p>
      </div>

      <div id="projects" phx-update="stream" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={{dom_id, row} <- @streams.projects}
          id={dom_id}
          navigate={~p"/projects/#{row.project}"}
          class="group rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-base-content/20 hover:shadow-md"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <h2 class="truncate font-semibold">{row.project.name}</h2>
              <p class="truncate font-mono text-xs text-base-content/50" title={row.project.key}>
                {row.project.key}
              </p>
            </div>
            <span
              :if={row.live_sessions > 0}
              class="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-sky-500/10 px-2 py-0.5 text-xs font-medium text-sky-700 dark:text-sky-300"
            >
              <.presence_dot presence={:working} /> {row.live_sessions} live
            </span>
          </div>
          <div class="mt-4 flex items-center gap-2">
            <%= for status <- Jarvis.Planning.Task.statuses() do %>
              <span class="inline-flex items-center gap-1 text-xs text-base-content/60">
                <.status_badge status={status} /> {Map.get(row.counts, status, 0)}
              </span>
            <% end %>
            <span class="ml-auto text-xs text-base-content/40">
              <.time_ago at={row.project.updated_at} now={@now} />
            </span>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
