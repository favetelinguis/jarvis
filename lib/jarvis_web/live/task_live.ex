defmodule JarvisWeb.TaskLive do
  @moduledoc """
  One task: its sections as the agent wrote them, its status and claim, the
  sessions focused on it, and a thread where the human talks to those agents.
  """
  use JarvisWeb, :live_view

  alias Jarvis.{Planning, Scope, Workspaces}
  alias Jarvis.Planning.Task
  alias Jarvis.Workspaces.AgentSession

  @impl true
  def mount(%{"project" => project_id, "goal" => goal, "task" => task}, _session, socket) do
    project = Workspaces.get_project!(project_id)
    if connected?(socket), do: Workspaces.subscribe(project.id)

    socket
    |> assign(:scope, Scope.for_human(project))
    |> assign(:goal_number, String.to_integer(goal))
    |> assign(:task_number, String.to_integer(task))
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
    %{scope: scope, task: task} = socket.assigns

    case Planning.add_comment(scope, task.goal, task, params) do
      {:ok, _} -> {:noreply, assign(socket, :form, to_form(%{"body" => ""}, as: :comment))}
      {:error, changeset} -> {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
    end
  end

  def handle_event("set_status", %{"status" => status}, socket)
      when status in ~w(todo ready done) do
    update(socket, %{"status" => status})
  end

  def handle_event("release", _params, socket), do: update(socket, %{"claim" => false})

  defp update(socket, attrs) do
    case Planning.update_task(socket.assigns.scope, socket.assigns.task, attrs) do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update the task.")}
    end
  end

  defp load(socket) do
    %{scope: scope, goal_number: goal, task_number: number} = socket.assigns

    case Planning.fetch_task(scope, goal, number) do
      {:ok, task} ->
        now = DateTime.utc_now()

        focused =
          scope.project
          |> Workspaces.list_sessions()
          |> Enum.filter(&(&1.task_id == task.id and AgentSession.presence(&1, now) != :ended))

        {:ok,
         socket
         |> assign(:task, task)
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
    ~H"""
    <Layouts.app
      flash={@flash}
      crumbs={[
        {@scope.project.name, ~p"/projects/#{@scope.project}"},
        {"Goal #{@task.goal.number}", ~p"/projects/#{@scope.project}/goals/#{@task.goal.number}"},
        {"Task #{@task.goal.number}.#{@task.number}",
         ~p"/projects/#{@scope.project}/goals/#{@task.goal.number}/tasks/#{@task.number}"}
      ]}
    >
      <header class="mb-8 flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <p class="font-mono text-xs text-base-content/40">
            Task {@task.goal.number}.{@task.number} · {@task.goal.title}
          </p>
          <h1 class="mt-1 text-2xl font-semibold tracking-tight">{@task.title}</h1>
          <div class="mt-3 flex flex-wrap items-center gap-2">
            <.status_badge status={@task.status} />
            <.questions_badge task={@task} />
            <.worktree_chip worktree={@task.worktree} />
          </div>
        </div>

        <div class="flex items-center gap-2">
          <div
            id="status-switch"
            class="inline-flex rounded-lg border border-base-300 bg-base-200 p-0.5"
          >
            <button
              :for={status <- Task.statuses()}
              id={"status-#{status}"}
              type="button"
              phx-click="set_status"
              phx-value-status={status}
              class={[
                "rounded-md px-2.5 py-1 text-xs font-medium transition",
                if(@task.status == status,
                  do: "bg-base-100 shadow-sm",
                  else: "text-base-content/60 hover:text-base-content"
                )
              ]}
            >
              {status}
            </button>
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
        </div>
      </header>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <article class="space-y-4">
          <%= for {field, label} <- Task.sections(), text = Map.fetch!(@task, field), text not in [nil, ""] do %>
            <.panel title={label} id={"task-#{field}"}>
              <.markdown text={text} />
            </.panel>
          <% end %>
          <p
            :if={
              Enum.all?(Task.sections(), fn {field, _} -> Map.fetch!(@task, field) in [nil, ""] end)
            }
            class="text-sm italic text-base-content/50"
          >
            Nothing written yet.
          </p>
        </article>

        <aside class="space-y-4">
          <.panel :if={@focused != []} title="Focused here" id="task-sessions">
            <.session_list sessions={@focused} now={@now} />
          </.panel>

          <.panel title="Conversation" id="task-comments">
            <.comment_thread comments={@task.comments} now={@now} />
            <.comment_form form={@form} />
          </.panel>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
