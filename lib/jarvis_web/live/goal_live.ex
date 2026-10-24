defmodule JarvisWeb.GoalLive do
  @moduledoc "One goal: its intent, scope, glossary, decisions, tasks, and the human's notes on it."
  use JarvisWeb, :live_view

  alias Jarvis.{Planning, Scope, Workspaces}
  alias Jarvis.Planning.Goal

  @impl true
  def mount(%{"project" => project_id, "goal" => number}, _session, socket) do
    project = Workspaces.get_project!(project_id)
    if connected?(socket), do: Workspaces.subscribe(project.id)

    socket
    |> assign(:scope, Scope.for_human(project))
    |> assign(:number, String.to_integer(number))
    |> assign(:form, to_form(%{"body" => ""}, as: :comment))
    |> load()
  end

  @impl true
  def handle_info({:jarvis, :changed}, socket) do
    {:ok, socket} = load(socket)
    {:noreply, socket}
  end

  @impl true
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
        {:ok,
         socket
         |> assign(:goal, goal)
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
    ~H"""
    <Layouts.app
      flash={@flash}
      crumbs={[
        {@scope.project.name, ~p"/projects/#{@scope.project}"},
        {"Goal #{@goal.number}", ~p"/projects/#{@scope.project}/goals/#{@goal.number}"}
      ]}
    >
      <header class="mb-8">
        <p class="font-mono text-xs text-base-content/40">Goal {@goal.number}</p>
        <h1 class="mt-1 text-2xl font-semibold tracking-tight">{@goal.title}</h1>
      </header>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <article class="space-y-4">
          <.panel :for={{field, label} <- Goal.sections()} title={label} id={"goal-#{field}"}>
            <.markdown text={Map.fetch!(@goal, field)} empty="Not written yet." />
          </.panel>
        </article>

        <aside class="space-y-4">
          <.panel title="Tasks" id="goal-tasks">
            <ul class="space-y-1">
              <li :if={@goal.tasks == []} class="text-sm text-base-content/50">No tasks yet.</li>
              <li :for={task <- @goal.tasks} id={"task-#{task.id}"}>
                <.link
                  navigate={
                    ~p"/projects/#{@scope.project}/goals/#{@goal.number}/tasks/#{task.number}"
                  }
                  class="flex items-center gap-2 rounded-lg px-2 py-1.5 text-sm transition hover:bg-base-200"
                >
                  <span class="font-mono text-xs text-base-content/40">{task.number}</span>
                  <span class="min-w-0 flex-1 truncate">{task.title}</span>
                  <.status_badge status={task.status} />
                </.link>
              </li>
            </ul>
          </.panel>

          <.panel title="Notes on this goal" id="goal-comments">
            <.comment_thread comments={@goal.comments} now={@now} />
            <.comment_form form={@form} />
          </.panel>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
