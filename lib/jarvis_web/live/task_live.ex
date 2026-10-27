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
    |> assign(:move_error, nil)
    |> assign(:picture_error, nil)
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
    do: {:noreply, assign(socket, confirming: name, move_error: nil)}

  def handle_event("move_cancel", _params, socket),
    do: {:noreply, assign(socket, confirming: nil, move_error: nil)}

  def handle_event("move", %{"transition" => name} = params, socket) do
    attrs = Map.take(params, ["comment", "new_title"])

    case Planning.move_task(socket.assigns.scope, socket.assigns.task, name, attrs) do
      {:ok, _} ->
        {:noreply, assign(socket, confirming: nil, move_error: nil)}

      {:error, %Ecto.Changeset{errors: errors}} ->
        case Keyword.take(errors, [:comment, :new_title]) do
          [{:comment, _} | _] ->
            {:noreply,
             assign(
               socket,
               :move_error,
               "Write a comment that says what to change. The task stays where it is."
             )}

          [{:new_title, _} | _] ->
            {:noreply, assign(socket, :move_error, "Give the new task a title.")}

          [] ->
            {:noreply,
             socket
             |> assign(confirming: nil, move_error: nil)
             |> put_flash(:error, "That move is not allowed right now.")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That move is not allowed right now.")}
    end
  end

  def handle_event("skip_quiz", _params, socket) do
    case Planning.skip_quiz(socket.assigns.scope, socket.assigns.task) do
      {:ok, _} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "The quiz can only be skipped in Quiz.")}
    end
  end

  def handle_event("save_picture", %{"picture" => text}, socket) do
    case Planning.save_picture(socket.assigns.scope, socket.assigns.task, text) do
      {:ok, _} ->
        {:noreply, assign(socket, :picture_error, nil)}

      {:error, _} ->
        {:noreply, assign(socket, :picture_error, "Write at least one concern, one per line.")}
    end
  end

  def handle_event("skip_picture", _params, socket) do
    {:ok, _} = Planning.save_picture(socket.assigns.scope, socket.assigns.task, nil)
    {:noreply, socket}
  end

  def handle_event("read_report", %{"report" => id}, socket) do
    {:ok, _} = Planning.read_report(socket.assigns.scope, id)
    {:noreply, socket}
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

        {reports, history} = Planning.list_reports(task.goal, task)
        view = Enum.find(widgets, &(&1.kind == "view_matches"))

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
         |> assign(:turn, Planning.turn(task))
         |> assign(:reports, reports)
         |> assign(:history, history)
         |> assign(:matches, if(view, do: Jarvis.Planning.Catalog.view_matches(view), else: %{}))
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
    hide_findings? = Planning.picture_pending?(assigns.task)

    assigns =
      assign(assigns,
        removed: Enum.filter(removed, &(&1.widget_id == nil)),
        hide_findings?: hide_findings?,
        page_path:
          ~p"/projects/#{assigns.scope.project}/goals/#{assigns.task.goal.number}/tasks/#{assigns.task.number}",
        sections: sections,
        current: current,
        ctx:
          context(
            ui: assigns.ui,
            comments: live,
            composer: assigns.composer,
            listening: Jarvis.Workspaces.AgentSession.listening(assigns.listener),
            changed: JarvisWeb.WidgetEvents.changed(assigns, assigns.reports),
            glossary: assigns.glossary,
            matches: assigns.matches,
            concerns: (assigns.task.picture || %{})["concerns"] || [],
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

      <.turn_panel
        task={@task}
        turn={@turn}
        transitions={@transitions}
        focused={@focused}
        widgets={@widgets}
        now={@now}
        path={@page_path}
      />

      <div :if={@reports != [] or @history != []} class="mb-6">
        <.turn_reports
          reports={@reports}
          history={@history}
          type={@task.type}
          path={@page_path}
          now={@now}
          hidden_sections={if @hide_findings?, do: ["findings"], else: []}
        />
      </div>

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
          move_error={@move_error}
        />
      </.panel>

      <div id="task-body" class="mt-6 space-y-6">
        <article id="task-content" class="space-y-8">
          <.section_toc
            sections={@sections}
            widgets={@widgets}
            type={@task.type}
            current={@current}
            path={~p"/projects/#{@scope.project}/goals/#{@task.goal.number}/tasks/#{@task.number}"}
          />
          <.picture_box
            :if={
              @task.type == :pr_review and @current in ~w(picture findings) and
                (@task.picture || %{})["state"] != "not_asked"
            }
            task={@task}
            matches={@matches}
            error={@picture_error}
          />
          <.sections
            sections={Enum.filter(@sections, &(elem(&1, 0) == @current))}
            widgets={
              if @hide_findings?,
                do: Enum.reject(@widgets, &(&1.section == "findings")),
                else: @widgets
            }
            ctx={@ctx}
            type={@task.type}
          />
          <.removed_anchors comments={@removed} />
        </article>

        <aside id="task-context" class="max-w-3xl space-y-4">
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

  attr :task, :map, required: true
  attr :turn, :any, required: true
  attr :transitions, :list, required: true
  attr :focused, :list, required: true
  attr :widgets, :list, required: true
  attr :now, DateTime, required: true
  attr :path, :string, required: true

  # Whose turn it is, and exactly what is expected: your decisions with what
  # each still lacks, or the command and worktree where the agent works.
  defp turn_panel(assigns) do
    decisions = Enum.filter(assigns.transitions, &(&1.t.mover == :human))
    working = Enum.filter(assigns.focused, &(AgentSession.presence(&1, assigns.now) == :working))

    assigns =
      assign(assigns,
        decisions: decisions,
        working: working,
        review: Enum.filter(assigns.widgets, &(&1.section == "review" and &1.kind == "findings")),
        evidence: assigns.widgets |> Enum.filter(&(&1.kind == "evidence")) |> List.last()
      )

    ~H"""
    <section
      id="turn"
      data-turn={turn_key(@turn)}
      aria-labelledby="turn-heading"
      class={[
        "mb-6 rounded-2xl p-4",
        if(@turn == :human,
          do: "border-2 border-base-content bg-base-100",
          else: "border border-base-300 bg-base-100"
        )
      ]}
    >
      <h2 id="turn-heading" class="flex flex-wrap items-center gap-2 text-lg font-semibold">
        <.turn_badge turn={@turn} />
        <%= case @turn do %>
          <% :human -> %>
            You decide what happens next.
          <% {:agent, _} -> %>
            An agent works on this step.
          <% _ -> %>
            This step ends the lifecycle.
        <% end %>
      </h2>

      <%= if @turn == :human do %>
        <ul id="open-decisions" class="mt-3 space-y-1.5 text-sm">
          <li :if={@decisions == []} class="italic text-base-content/70">
            No decision is open in this step.
          </li>
          <li :for={%{t: t, unmet: unmet} <- @decisions} id={"decision-#{dashed(t.name)}"}>
            <a href={"#transition-#{dashed(t.name)}"} class="font-medium underline">{t.name}</a>
            → {TaskType.step_label(@task.type, t.to)}: <span :if={unmet == []}>ready.</span>
            <span :if={unmet != []} data-role="missing">
              still missing: {Enum.join(unmet, "; ")}.
            </span>
          </li>
        </ul>
        <button
          :if={@task.type == :pr_review and @task.step == "quiz" and !@task.quiz_skipped}
          id="skip-quiz"
          type="button"
          phx-click="skip_quiz"
          data-confirm="Skip the quiz and let the agent write its findings?"
          class="mt-3 rounded-lg border border-base-300 px-3 py-1.5 text-sm font-medium transition hover:bg-base-200"
        >
          Skip quiz
        </button>
      <% end %>

      <%= case @turn do %>
        <% {:agent, command} -> %>
          <p id="turn-command" class="mt-2 text-sm">
            <%= if command do %>
              Run <code class="rounded bg-base-200 px-1">{command}</code>
            <% else %>
              An agent continues
            <% end %>
            <%= if @task.worktree do %>
              in worktree <strong>{@task.worktree.name}</strong>.
            <% else %>
              in the worktree that should take it up; no worktree has claimed this task yet.
            <% end %>
          </p>
          <p id="turn-session" class="mt-1 text-sm text-base-content/70">
            <%= case @working do %>
              <% [] -> %>
                No session is working on it right now.
              <% sessions -> %>
                {Enum.map_join(sessions, ", ", &session_name/1)} is working on it now.
            <% end %>
          </p>
          <p :if={@decisions != []} class="mt-1 text-sm text-base-content/70">
            Your buttons still work: {Enum.map_join(@decisions, ", ", & &1.t.name)}.
          </p>
        <% _ -> %>
      <% end %>

      <div
        :if={@task.type == :feature and @task.step in ~w(design acceptance)}
        id="turn-evidence"
        class="mt-3 grid gap-2 text-sm md:grid-cols-2"
      >
        <div id="turn-review" class="rounded-xl bg-base-200/60 p-3">
          <p class="font-medium">Review in a fresh context</p>
          <%= case @review do %>
            <% [] -> %>
              <p>No review report yet.</p>
            <% widgets -> %>
              <% findings = Enum.flat_map(widgets, & &1.data["findings"]) %>
              <p>
                {if findings == [],
                  do: "No findings.",
                  else:
                    "#{length(findings)} finding(s): #{findings |> Enum.frequencies_by(& &1["severity"]) |> Enum.map_join(", ", fn {k, v} -> "#{v} #{k}" end)}."}
                <span :if={Enum.any?(widgets, & &1.human["stale"])} class="font-semibold">Out of date.</span>
              </p>
              <.link patch={"#{@path}?section=review"} class="underline">Read the review</.link>
          <% end %>
        </div>
        <div :if={@task.step == "acceptance"} id="turn-proof" class="rounded-xl bg-base-200/60 p-3">
          <p class="font-medium">Evidence</p>
          <%= case @evidence do %>
            <% nil -> %>
              <p>No evidence recorded.</p>
            <% w -> %>
              <% rows = w.data["requirements"] %>
              <p>
                Check {w.data["result"]}; {Enum.count(rows, &(&1["result"] == "passed"))} of {length(
                  rows
                )} tests passed.
                <span :if={w.human["stale"]} class="font-semibold">Out of date.</span>
              </p>
              <.link patch={"#{@path}?section=evidence"} class="underline">Read the evidence</.link>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  attr :task, :map, required: true
  attr :matches, :map, required: true
  attr :error, :string, default: nil

  # The human's own concerns about a pull request, written before the agent's
  # first-round findings are shown.
  defp picture_box(assigns) do
    picture = assigns.task.picture || %{}
    covered = assigns.matches |> Map.values() |> Enum.reject(&is_nil/1) |> MapSet.new()

    assigns =
      assign(assigns,
        picture: picture,
        pending?: Planning.picture_pending?(assigns.task),
        covered: covered,
        matched?: assigns.matches != %{}
      )

    ~H"""
    <section id="picture" class="rounded-2xl border-2 border-base-content/70 bg-base-100 p-4">
      <h2 class="text-sm font-semibold">Your view</h2>
      <%= if @pending? do %>
        <p class="mt-1 text-sm">
          Write your own concerns about this pull request before you see the agent's findings.
          The findings stay hidden until you save or skip.
        </p>
      <% end %>
      <ul :if={@picture["state"] == "saved"} id="picture-concerns" class="mt-2 space-y-1 text-sm">
        <li
          :for={c <- @picture["concerns"]}
          id={"concern-#{c["id"]}"}
          class="flex flex-wrap items-center gap-2"
        >
          <span class="font-mono text-xs">{c["id"]}</span>
          <span>{c["text"]}</span>
          <span
            :if={@matched? and not MapSet.member?(@covered, c["id"])}
            id={"concern-badge-#{c["id"]}"}
            class="rounded-md border border-base-content/40 px-1.5 py-0.5 text-[0.6875rem] font-semibold"
          >
            Only you
          </span>
        </li>
      </ul>
      <p :if={@picture["state"] == "skipped"} class="mt-1 text-sm text-base-content/70">
        You skipped your view.
      </p>
      <form
        :if={@picture["state"] != "not_asked"}
        id="picture-form"
        phx-submit="save_picture"
        class="mt-3 space-y-2"
      >
        <label for="picture-text" class="text-sm font-medium">
          {if @picture["state"] == "saved",
            do: "Change your concerns",
            else: "Your concerns, one per line"}
        </label>
        <textarea
          id="picture-text"
          name="picture"
          rows="4"
          aria-invalid={@error && "true"}
          aria-describedby={@error && "picture-error"}
          class="w-full rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-sm"
        >{@picture["text"]}</textarea>
        <p :if={@error} id="picture-error" role="alert" class="text-sm text-error">{@error}</p>
        <div class="flex flex-wrap gap-2">
          <button
            id="save-picture"
            type="submit"
            class="rounded-lg bg-base-content px-3 py-1.5 text-sm font-medium text-base-100 hover:opacity-85"
          >
            Save your view
          </button>
          <button
            :if={@pending?}
            id="skip-picture"
            type="button"
            phx-click="skip_picture"
            class="rounded-lg border border-base-300 px-3 py-1.5 text-sm font-medium hover:bg-base-200"
          >
            Skip and show the findings
          </button>
        </div>
      </form>
    </section>
    """
  end

  defp dashed(name), do: String.replace(name, " ", "-")
end
