defmodule JarvisWeb.ProjectLive do
  @moduledoc """
  One project at a glance: goals with their tasks, which agent sessions are
  live and what they focus on, mirrored session transcripts, and the activity feed.
  """
  use JarvisWeb, :live_view

  alias Jarvis.{Planning, Scope, Transcripts, Workspaces}
  alias Jarvis.Workspaces.AgentSession

  @type filter :: :all | :unfinished | :todo | :ready | :done

  @tick_ms 20_000

  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def mount(%{"project" => id}, _session, socket) do
    project = Workspaces.get_project!(id)

    if connected?(socket) do
      Workspaces.subscribe(project.id)
      :timer.send_interval(@tick_ms, :tick)
    end

    {:ok,
     socket
     |> assign(:page_title, project.name)
     |> assign(:scope, Scope.for_human(project))
     |> assign(:filter, :all)
     |> load()}
  end

  @spec handle_info({:jarvis, :changed} | :tick, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_info({:jarvis, :changed}, socket), do: {:noreply, load(socket)}
  def handle_info(:tick, socket), do: {:noreply, assign(socket, :now, DateTime.utc_now())}

  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_event("filter", params, socket) do
    filter =
      case Map.get(params, "filter") do
        "all" -> :all
        "unfinished" -> :unfinished
        "todo" -> :todo
        "ready" -> :ready
        "done" -> :done
        _ -> socket.assigns.filter
      end

    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  @spec load(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load(socket) do
    scope = socket.assigns.scope
    goals = Planning.list_goals(scope)

    matching_goals =
      Enum.filter(goals, &(matching_tasks(&1.tasks, socket.assigns.filter) != []))

    sessions = Workspaces.list_sessions(scope.project)
    now = DateTime.utc_now()

    # Which live sessions focus on each task, to mark the task as being worked on.
    focus =
      sessions
      |> Enum.filter(&(&1.task_id && AgentSession.presence(&1, now) in [:working, :idle]))
      |> Enum.group_by(& &1.task_id)

    socket
    |> assign(:now, now)
    |> assign(:sessions, sessions)
    |> assign(:focus, focus)
    |> assign(:goal_count, length(goals))
    |> assign(:matching_goals_empty?, matching_goals == [])
    |> assign(:transcripts, Transcripts.list_transcripts(scope.project.id, 15))
    |> stream(:goals, matching_goals, reset: true)
    |> stream(:events, Planning.list_events(scope, 40), reset: true)
  end

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} crumbs={[{@scope.project.name, ~p"/projects/#{@scope.project}"}]}>
      <div class="mb-8 flex flex-wrap items-end justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-2xl font-semibold tracking-tight">{@scope.project.name}</h1>
          <p class="truncate font-mono text-xs text-base-content/50">{@scope.project.key}</p>
        </div>
      </div>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <div class="space-y-4">
          <div
            id="task-filter"
            role="group"
            aria-label="Filter tasks"
            class="flex flex-wrap gap-1 rounded-xl border border-base-300 bg-base-200/50 p-1"
          >
            <button
              :for={
                {filter, label} <- [
                  all: "All",
                  unfinished: "Unfinished",
                  todo: "Todo",
                  ready: "Ready",
                  done: "Done"
                ]
              }
              id={"filter-#{filter}"}
              type="button"
              phx-click="filter"
              phx-value-filter={filter}
              aria-pressed={to_string(@filter == filter)}
              class={[
                "rounded-lg px-3 py-1.5 text-sm font-medium transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-base-content",
                if(@filter == filter,
                  do: "bg-base-100 text-base-content shadow-sm",
                  else: "text-base-content/60 hover:bg-base-100/60 hover:text-base-content"
                )
              ]}
            >
              {label}
            </button>
          </div>

          <div
            :if={@goal_count > 0 and @matching_goals_empty?}
            id="no-matching-tasks"
            class="rounded-2xl border border-dashed border-base-300 p-10 text-center text-sm text-base-content/60"
          >
            No matching tasks. Choose another filter to see more work.
          </div>

          <div
            :if={@goal_count == 0}
            id="no-goals"
            class="rounded-2xl border border-dashed border-base-300 p-10 text-center text-sm text-base-content/60"
          >
            No goals yet. Ask an agent to <code class="rounded bg-base-200 px-1">/specify</code> one.
          </div>

          <div id="goals" phx-update="stream" class="space-y-4">
            <section
              :for={{dom_id, goal} <- @streams.goals}
              id={dom_id}
              class="rounded-2xl border border-base-300 bg-base-100 shadow-sm"
            >
              <.link
                navigate={~p"/projects/#{@scope.project}/goals/#{goal.number}"}
                class="group flex items-center gap-3 rounded-t-2xl px-5 py-4 transition hover:bg-base-200/50"
              >
                <span class="font-mono text-xs text-base-content/40">G{goal.number}</span>
                <h2 class="min-w-0 flex-1 truncate font-semibold group-hover:underline">
                  {goal.title}
                </h2>
                <.progress tasks={goal.tasks} />
              </.link>
              <ul class="divide-y divide-base-200 border-t border-base-200">
                <li :for={task <- matching_tasks(goal.tasks, @filter)} id={"task-#{task.id}"}>
                  <.link
                    navigate={
                      ~p"/projects/#{@scope.project}/goals/#{goal.number}/tasks/#{task.number}"
                    }
                    class="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-2.5 transition hover:bg-base-200/50"
                  >
                    <span class="w-10 font-mono text-xs text-base-content/40">
                      {goal.number}.{task.number}
                    </span>
                    <.status_badge status={task.status} />
                    <span class={[
                      "min-w-0 flex-1 truncate text-sm",
                      task.status == :done && "text-base-content/50"
                    ]}>
                      {task.title}
                    </span>
                    <.questions_badge task={task} />
                    <.worktree_chip worktree={task.worktree} />
                    <span
                      :for={session <- Map.get(@focus, task.id, [])}
                      class="inline-flex items-center gap-1 text-xs text-base-content/60"
                      title={"#{session_name(session)} is #{presence_label(AgentSession.presence(session, @now))}"}
                    >
                      <.presence_dot presence={AgentSession.presence(session, @now)} />
                    </span>
                  </.link>
                </li>
              </ul>
            </section>
          </div>
        </div>

        <aside class="space-y-4">
          <.panel title="Agent sessions" id="sessions-panel">
            <.session_list sessions={@sessions} now={@now} />
          </.panel>

          <.panel title="Transcripts" id="transcripts-panel">
            <ul id="transcripts" class="space-y-1">
              <li :if={@transcripts == []} class="px-2 py-3 text-sm text-base-content/50">
                No mirrored sessions yet.
              </li>
              <li :for={t <- @transcripts} id={"transcript-#{t.id}"}>
                <.link
                  navigate={~p"/transcripts/#{t.id}"}
                  class="block rounded-lg px-2 py-2 transition hover:bg-base-200"
                >
                  <div class="flex items-center gap-2">
                    <.harness_badge harness={t.harness} />
                    <span class="min-w-0 flex-1 truncate text-sm">{t.title || t.external_id}</span>
                  </div>
                  <div class="mt-1 flex items-center gap-2 pl-1 text-xs text-base-content/50">
                    <.worktree_chip worktree={t.worktree} />
                    <span>{t.line_count} lines</span>
                    <span :if={t.last_entry_at} class="ml-auto">
                      <.time_ago at={t.last_entry_at} now={@now} />
                    </span>
                  </div>
                </.link>
              </li>
            </ul>
          </.panel>

          <.panel title="Activity" id="activity-panel">
            <ol id="events" phx-update="stream" class="space-y-2.5">
              <li id="events-empty" class="hidden text-sm text-base-content/50 only:block">
                Nothing has happened yet.
              </li>
              <li :for={{dom_id, event} <- @streams.events} id={dom_id} class="flex gap-2 text-sm">
                <.icon
                  name={if event.actor == :human, do: "hero-user-mini", else: "hero-cpu-chip-mini"}
                  class="mt-0.5 size-4 shrink-0 text-base-content/40"
                />
                <div class="min-w-0">
                  <p class="break-words">
                    <span class="font-medium">
                      {if event.agent_session, do: session_name(event.agent_session), else: "You"}
                    </span>
                    {event.summary}
                  </p>
                  <p class="text-xs text-base-content/40">
                    <.time_ago at={event.inserted_at} now={@now} />
                  </p>
                </div>
              </li>
            </ol>
          </.panel>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  @spec matching_tasks(list(), filter()) :: list()
  defp matching_tasks(tasks, filter) do
    Enum.filter(tasks, fn task ->
      case filter do
        :all -> true
        :unfinished -> task.status in [:todo, :ready]
        status -> task.status == status
      end
    end)
  end

  attr :tasks, :list, required: true

  defp progress(assigns) do
    counts = Enum.frequencies_by(assigns.tasks, & &1.status)
    total = max(length(assigns.tasks), 1)
    assigns = assign(assigns, counts: counts, total: total)

    ~H"""
    <div
      class="flex items-center gap-2"
      title={"#{Map.get(@counts, :done, 0)} of #{length(@tasks)} done"}
    >
      <div class="flex h-1.5 w-24 overflow-hidden rounded-full bg-base-200">
        <div class="bg-emerald-500" style={"width: #{Map.get(@counts, :done, 0) * 100 / @total}%"} />
        <div class="bg-amber-400" style={"width: #{Map.get(@counts, :ready, 0) * 100 / @total}%"} />
      </div>
      <span class="font-mono text-xs text-base-content/50">
        {Map.get(@counts, :done, 0)}/{length(@tasks)}
      </span>
    </div>
    """
  end
end
