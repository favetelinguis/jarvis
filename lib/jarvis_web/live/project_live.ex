defmodule JarvisWeb.ProjectLive do
  @moduledoc """
  One project at a glance: goals with their tasks, which agent sessions are
  live and what they focus on, mirrored session transcripts, and the activity feed.
  """
  use JarvisWeb, :live_view

  alias Jarvis.{Planning, Scope, Transcripts, Workspaces}
  alias Jarvis.Planning.TaskType
  alias Jarvis.Workspaces.AgentSession

  @type filter :: %{unfinished: boolean(), type: TaskType.key() | nil, step: String.t() | nil}

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
     |> assign(:filter, %{unfinished: false, type: nil, step: nil})
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
  def handle_event("filter", %{"filter" => "unfinished"}, socket),
    do: {:noreply, socket |> update_filter(&%{&1 | unfinished: not &1.unfinished}) |> load()}

  def handle_event("filter", _params, socket),
    do:
      {:noreply,
       socket |> update_filter(fn _ -> %{unfinished: false, type: nil, step: nil} end) |> load()}

  def handle_event("type", %{"type" => type}, socket) do
    type = TaskType.parse(type)

    {:noreply,
     socket
     |> update_filter(&%{&1 | type: if(&1.type == type, do: nil, else: type), step: nil})
     |> load()}
  end

  def handle_event("step", %{"step" => step}, socket) do
    {:noreply,
     socket |> update_filter(&%{&1 | step: if(&1.step == step, do: nil, else: step)}) |> load()}
  end

  defp update_filter(socket, fun), do: assign(socket, :filter, fun.(socket.assigns.filter))

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
    <Layouts.app
      flash={@flash}
      theme_css={@theme_css}
      crumbs={[{@scope.project.name, ~p"/projects/#{@scope.project}"}]}
    >
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
            class="space-y-2 rounded-xl border border-base-300 bg-base-200/50 p-1"
          >
            <div class="flex flex-wrap gap-1">
              <.filter_button
                id="filter-all"
                event="filter"
                value={%{filter: "all"}}
                active={@filter == %{unfinished: false, type: nil, step: nil}}
              >All</.filter_button>
              <.filter_button
                id="filter-unfinished"
                event="filter"
                value={%{filter: "unfinished"}}
                active={@filter.unfinished}
              >Unfinished</.filter_button>
              <span class="mx-1 w-px self-stretch bg-base-300" />
              <.filter_button
                :for={type <- TaskType.keys()}
                id={"type-#{type}"}
                event="type"
                value={%{type: type}}
                active={@filter.type == type}
              >
                {TaskType.label(type)}
              </.filter_button>
            </div>
            <div :if={@filter.type} id="step-filter" class="flex flex-wrap gap-1">
              <.filter_button
                :for={{key, label, _} <- TaskType.steps(@filter.type)}
                id={"step-#{key}"}
                event="step"
                value={%{step: key}}
                active={@filter.step == key}
              >
                {label}
              </.filter_button>
            </div>
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
                    <.type_badge type={task.type} />
                    <.step_badge step={task.step} label={TaskType.step_label(task.type, task.step)} />
                    <span class={[
                      "min-w-0 flex-1 truncate text-sm",
                      task.step == "done" && "text-base-content/50"
                    ]}>
                      {task.title}
                    </span>
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
      (not filter.unfinished or task.step != "done") and
        (filter.type == nil or task.type == filter.type) and
        (filter.step == nil or task.step == filter.step)
    end)
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :value, :map, required: true
  attr :active, :boolean, required: true
  slot :inner_block, required: true

  defp filter_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click={@event}
      {for {k, v} <- @value, do: {:"phx-value-#{k}", v}}
      aria-pressed={to_string(@active)}
      class={[
        "rounded-lg px-3 py-1.5 text-sm font-medium transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
        if(@active,
          do: "bg-primary text-primary-content shadow-sm",
          else: "text-base-content/70 hover:bg-base-100/60 hover:text-base-content"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :tasks, :list, required: true

  defp progress(assigns) do
    done = Enum.count(assigns.tasks, &(&1.step == "done"))
    assigns = assign(assigns, done: done, total: max(length(assigns.tasks), 1))

    ~H"""
    <div class="flex items-center gap-2" title={"#{@done} of #{length(@tasks)} done"}>
      <div class="flex h-1.5 w-24 overflow-hidden rounded-full bg-base-200">
        <div class="bg-success" style={"width: #{@done * 100 / @total}%"} />
      </div>
      <span class="font-mono text-xs text-base-content/60">{@done}/{length(@tasks)}</span>
    </div>
    """
  end
end
