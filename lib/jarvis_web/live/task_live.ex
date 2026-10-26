defmodule JarvisWeb.TaskLive do
  @moduledoc """
  One task: its lifecycle as a graph with the moves out of the current step,
  its sections as widgets the human can comment on, the sessions focused on
  it, and a thread where the human talks to those agents.
  """
  use JarvisWeb, :live_view

  alias Jarvis.{Planning, Scope, Workspaces}
  alias Jarvis.Planning.{Comment, TaskType}
  alias Jarvis.Workspaces.AgentSession

  import JarvisWeb.WidgetComponents

  @impl true
  def mount(%{"project" => project_id, "goal" => goal, "task" => task}, _session, socket) do
    project = Workspaces.get_project!(project_id)
    if connected?(socket), do: Workspaces.subscribe(project.id)

    socket
    |> assign(:scope, Scope.for_human(project))
    |> assign(:goal_number, String.to_integer(goal))
    |> assign(:task_number, String.to_integer(task))
    |> assign(:form, to_form(%{"body" => ""}, as: :comment))
    |> assign(:ui, %{})
    |> assign(:composer, nil)
    |> assign(:confirming, nil)
    |> load()
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, :section_param, params["section"])}

  @impl true
  def handle_info({:jarvis, :changed}, socket) do
    {:ok, socket} = load(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("widget:" <> _ = event, params, socket),
    do: JarvisWeb.WidgetEvents.handle(event, params, socket)

  def handle_event("comment", %{"comment" => params}, socket) do
    %{scope: scope, task: task} = socket.assigns

    case Planning.add_comment(scope, task.goal, task, params) do
      {:ok, _} -> {:noreply, assign(socket, :form, to_form(%{"body" => ""}, as: :comment))}
      {:error, changeset} -> {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
    end
  end

  def handle_event("move_ask", %{"transition" => name}, socket),
    do: {:noreply, assign(socket, :confirming, name)}

  def handle_event("move_cancel", _params, socket),
    do: {:noreply, assign(socket, :confirming, nil)}

  def handle_event("move", %{"transition" => name}, socket) do
    socket = assign(socket, :confirming, nil)

    case Planning.move_task(socket.assigns.scope, socket.assigns.task, name) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "That move is not allowed right now.")}
    end
  end

  def handle_event("release", _params, socket) do
    case Planning.update_task(socket.assigns.scope, socket.assigns.task, %{"claim" => false}) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update the task.")}
    end
  end

  defp load(socket) do
    %{scope: scope, goal_number: goal, task_number: number} = socket.assigns

    case Planning.fetch_task(scope, goal, number) do
      {:ok, task} ->
        now = DateTime.utc_now()
        widgets = Planning.list_widgets(task.goal, task)
        {anchored, plain} = Enum.split_with(task.comments, &Comment.anchored?/1)

        focused =
          scope.project
          |> Workspaces.list_sessions()
          |> Enum.filter(&(&1.task_id == task.id and AgentSession.presence(&1, now) != :ended))

        transitions =
          for t <- TaskType.transitions_from(task.type, task.step),
              do: %{t: t, unmet: Planning.unmet_conditions(task, t, widgets)}

        {:ok,
         socket
         |> assign(:task, task)
         |> assign(
           :glossary,
           JarvisWeb.WidgetComponents.glossary(
             Planning.list_widgets(task.goal, nil),
             Jarvis.Language.current()
           )
         )
         |> assign(:goal, task.goal)
         |> JarvisWeb.WidgetEvents.assign_widgets(widgets)
         |> assign(:anchored, anchored)
         |> assign(:plain, plain)
         |> assign(:transitions, transitions)
         |> assign(:listener, Planning.listening_session(scope.project, task.goal, task))
         |> assign(:focused, focused)
         |> assign(:now, now)
         |> assign(:page_title, "#{Planning.ref(task)}: #{task.title}")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(:task, nil)
         |> put_flash(:error, "That task does not exist.")
         |> push_navigate(to: ~p"/projects/#{scope.project}")}
    end
  end

  # The section in the URL, else the first one with widgets, else the first.
  defp current_section(sections, widgets, param) do
    keys = Enum.map(sections, &elem(&1, 0))
    filled = MapSet.new(widgets, & &1.section)

    cond do
      param in keys -> param
      key = Enum.find(keys, &MapSet.member?(filled, &1)) -> key
      true -> hd(keys)
    end
  end

  @impl true
  def render(%{task: nil} = assigns), do: ~H""

  def render(assigns) do
    ids = MapSet.new(assigns.widgets, & &1.id)
    sections = TaskType.sections(assigns.task.type)
    current = current_section(sections, assigns.widgets, assigns[:section_param])
    {live, removed} = Enum.split_with(assigns.anchored, &(&1.widget_id in ids))

    assigns =
      assign(assigns,
        removed: Enum.filter(removed, &(&1.widget_id == nil)),
        sections: sections,
        current: current,
        ctx:
          context(
            ui: assigns.ui,
            comments: live,
            composer: assigns.composer,
            listening: Jarvis.Workspaces.AgentSession.listening(assigns.listener),
            changed: assigns.changed,
            glossary: assigns.glossary,
            now: assigns.now
          )
      )

    ~H"""
    <Layouts.app
      form={JarvisWeb.Diataxis.task_page(@task.type)}
      flash={@flash}
      theme_css={@theme_css}
      crumbs={[
        {@scope.project.name, ~p"/projects/#{@scope.project}"},
        {"Goal #{@task.goal.number}", ~p"/projects/#{@scope.project}/goals/#{@task.goal.number}"},
        {"Task #{@task.goal.number}.#{@task.number} (#{TaskType.step_label(@task.type, @task.step)})",
         ~p"/projects/#{@scope.project}/goals/#{@task.goal.number}/tasks/#{@task.number}"}
      ]}
    >
      <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="font-mono text-xs text-base-content/70">
            Task {@task.goal.number}.{@task.number} · {@task.goal.title}
          </p>
          <h1 class="mt-1 text-2xl font-semibold tracking-tight">{@task.title}</h1>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <.poc_badge :if={@task.goal.poc} />
            <.type_badge type={@task.type} />
            <.step_badge step={@task.step} label={TaskType.step_label(@task.type, @task.step)} />
            <.worktree_chip worktree={@task.worktree} />
          </div>
          <div id="where-next" class="mt-3 text-sm">
            <p>
              You are in step <strong>{TaskType.step_label(@task.type, @task.step)}</strong>
              of task {@task.goal.number}.{@task.number}.
            </p>
            <p :if={@transitions == []}>Next: nothing. This step ends the lifecycle.</p>
            <p :if={@transitions != []}>
              Next:
              <%= for {%{t: t, unmet: unmet}, i} <- Enum.with_index(@transitions) do %>
                <span :if={i > 0}>; </span>
                <a href={"#transition-#{String.replace(t.name, " ", "-")}"} class="underline">{t.name}</a>
                ({if t.mover == :human, do: "you", else: "an agent"}<span :if={unmet != []}>, blocked</span>)
              <% end %>
            </p>
          </div>
        </div>

        <button
          :if={@task.worktree}
          id="release-claim"
          type="button"
          phx-click="release"
          data-confirm="Release this task from its worktree?"
          class="rounded-lg border border-base-300 px-2.5 py-1 text-xs font-medium text-base-content/70 transition hover:bg-base-200"
        >
          Release claim
        </button>
      </header>

      <.panel title="Lifecycle" id="task-lifecycle">
        <:actions>
          <.link
            id="lifecycle-guide"
            navigate={JarvisWeb.GuideLive.path(@task.type)}
            class="flex items-center gap-1 rounded px-1.5 py-0.5 text-xs text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
          >
            <.icon name="hero-book-open-mini" class="size-4" /> Guide
          </.link>
        </:actions>
        <.lifecycle
          type={@task.type}
          step={@task.step}
          previous={@task.previous_step}
          transitions={@transitions}
          confirming={@confirming}
        />
      </.panel>

      <div class="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <article class="space-y-8">
          <.section_toc
            sections={@sections}
            widgets={@widgets}
            type={@task.type}
            current={@current}
            path={~p"/projects/#{@scope.project}/goals/#{@task.goal.number}/tasks/#{@task.number}"}
          />
          <.sections
            sections={Enum.filter(@sections, &(elem(&1, 0) == @current))}
            widgets={@widgets}
            ctx={@ctx}
            type={@task.type}
          />
          <.removed_anchors comments={@removed} />
        </article>

        <aside class="space-y-4">
          <.panel title="Who hears your comments" id="task-listener">
            <p :if={@listener} class="flex items-center gap-2 text-sm">
              <.presence_dot presence={AgentSession.presence(@listener, @now)} />
              {session_name(@listener)} is listening.
            </p>
            <p :if={!@listener} class="text-sm text-base-content/70">
              No agent listening. Comments on widgets wait until a session takes up this task.
            </p>
          </.panel>

          <.panel :if={@focused != []} title="Focused here" id="task-sessions">
            <.session_list sessions={@focused} now={@now} />
          </.panel>

          <.panel title="Conversation" id="task-comments">
            <.comment_thread comments={@plain} now={@now} />
            <.comment_form form={@form} />
          </.panel>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
