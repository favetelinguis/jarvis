defmodule JarvisWeb.GoalLive do
  @moduledoc "One goal: its sections as widgets, its tasks, and the human's notes on it."
  use JarvisWeb, :live_view

  alias Jarvis.{Planning, Scope, Workspaces}
  alias Jarvis.Planning.{Comment, TaskType}

  import JarvisWeb.WidgetComponents

  @impl true
  def mount(%{"project" => project_id, "goal" => number}, _session, socket) do
    project = Workspaces.get_project!(project_id)
    if connected?(socket), do: Workspaces.subscribe(project.id)

    socket
    |> assign(:scope, Scope.for_human(project))
    |> assign(:number, String.to_integer(number))
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
    %{scope: scope, goal: goal} = socket.assigns

    case Planning.add_comment(scope, goal, nil, params) do
      {:ok, _} -> {:noreply, assign(socket, :form, to_form(%{"body" => ""}, as: :comment))}
      {:error, changeset} -> {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
    end
  end

  defp load(socket) do
    case Planning.fetch_goal(socket.assigns.scope, socket.assigns.number) do
      {:ok, goal} ->
        widgets = Planning.list_widgets(goal, nil)
        {anchored, plain} = Enum.split_with(goal.comments, &Comment.anchored?/1)

        {:ok,
         socket
         |> assign(:goal, goal)
         |> assign(:widgets, widgets)
         |> assign(:anchored, anchored)
         |> assign(:plain, plain)
         |> assign(:listener, Planning.listening_session(socket.assigns.scope.project, goal, nil))
         |> assign(:page_title, "#{Planning.ref(goal)}: #{goal.title}")
         |> assign(:now, DateTime.utc_now())}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That goal does not exist.")
         |> push_navigate(to: ~p"/projects/#{socket.assigns.scope.project}")
         |> assign(:goal, nil)}
    end
  end

  @impl true
  def render(%{goal: nil} = assigns), do: ~H""

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
            listening: Jarvis.Workspaces.AgentSession.listening(assigns.listener),
            now: assigns.now
          )
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      theme_css={@theme_css}
      crumbs={[
        {@scope.project.name, ~p"/projects/#{@scope.project}"},
        {"Goal #{@goal.number}", ~p"/projects/#{@scope.project}/goals/#{@goal.number}"}
      ]}
    >
      <header class="mb-8">
        <p class="font-mono text-xs text-base-content/60">Goal {@goal.number}</p>
        <h1 class="mt-1 text-2xl font-semibold tracking-tight">{@goal.title}</h1>
      </header>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <article class="space-y-8">
          <.sections sections={TaskType.sections(:goal)} widgets={@widgets} ctx={@ctx} prefix="goal" />
          <.removed_anchors comments={@removed} />
        </article>

        <aside class="space-y-4">
          <.panel title="Tasks" id="goal-tasks">
            <ul class="space-y-1">
              <li :if={@goal.tasks == []} class="text-sm text-base-content/60">No tasks yet.</li>
              <li :for={task <- @goal.tasks} id={"task-#{task.id}"}>
                <.link
                  navigate={
                    ~p"/projects/#{@scope.project}/goals/#{@goal.number}/tasks/#{task.number}"
                  }
                  class="flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm transition hover:bg-base-200"
                >
                  <span class="font-mono text-xs text-base-content/60">{task.number}</span>
                  <span class="min-w-0 flex-1 truncate">{task.title}</span>
                  <.type_badge type={task.type} />
                  <.step_badge step={task.step} label={TaskType.step_label(task.type, task.step)} />
                </.link>
              </li>
            </ul>
          </.panel>

          <.panel title="Notes on this goal" id="goal-comments">
            <.comment_thread comments={@plain} now={@now} />
            <.comment_form form={@form} />
          </.panel>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
