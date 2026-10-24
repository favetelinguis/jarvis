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
    |> load()
  end

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

  def handle_event("move", %{"transition" => name}, socket) do
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
         |> assign(:goal, task.goal)
         |> assign(:widgets, widgets)
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

  @impl true
  def render(%{task: nil} = assigns), do: ~H""

  def render(assigns) do
    ids = MapSet.new(assigns.widgets, & &1.id)
    {live, removed} = Enum.split_with(assigns.anchored, &(&1.widget_id in ids))

    assigns =
      assign(assigns,
        removed: Enum.filter(removed, &(&1.widget_id == nil)),
        ctx:
          context(
            ui: assigns.ui,
            comments: live,
            composer: assigns.composer,
            listening: assigns.listener != nil,
            now: assigns.now
          )
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      theme_css={@theme_css}
      crumbs={[
        {@scope.project.name, ~p"/projects/#{@scope.project}"},
        {"Goal #{@task.goal.number}", ~p"/projects/#{@scope.project}/goals/#{@task.goal.number}"},
        {"Task #{@task.goal.number}.#{@task.number}",
         ~p"/projects/#{@scope.project}/goals/#{@task.goal.number}/tasks/#{@task.number}"}
      ]}
    >
      <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="font-mono text-xs text-base-content/60">
            Task {@task.goal.number}.{@task.number} · {@task.goal.title}
          </p>
          <h1 class="mt-1 text-2xl font-semibold tracking-tight">{@task.title}</h1>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <.type_badge type={@task.type} />
            <.step_badge step={@task.step} label={TaskType.step_label(@task.type, @task.step)} />
            <.worktree_chip worktree={@task.worktree} />
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
        <.lifecycle
          type={@task.type}
          step={@task.step}
          previous={@task.previous_step}
          transitions={@transitions}
        />
      </.panel>

      <div class="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <article class="space-y-8">
          <.sections sections={TaskType.sections(@task.type)} widgets={@widgets} ctx={@ctx} />
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
