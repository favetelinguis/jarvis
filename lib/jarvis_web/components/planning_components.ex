defmodule JarvisWeb.PlanningComponents do
  @moduledoc "Building blocks shared by the project, goal, and task pages."
  use JarvisWeb, :verified_routes
  use Phoenix.Component

  import JarvisWeb.CoreComponents, only: [icon: 1]

  alias Jarvis.Planning.TaskType
  alias Jarvis.Workspaces.{AgentSession, Worktree}

  attr :step, :string, required: true
  attr :label, :string, default: nil

  @doc "A task's lifecycle step; Done is green, everything else the primary color."
  def step_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset",
      if(@step == "done",
        do: "bg-emerald-500/10 text-emerald-700 ring-emerald-500/30 dark:text-emerald-300",
        else: "bg-primary/10 text-primary ring-primary/30"
      )
    ]}>
      {@label || @step}
    </span>
    """
  end

  attr :type, :atom, required: true

  def type_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 rounded-md bg-base-200 px-1.5 py-0.5 text-[11px] font-medium text-base-content/70">
      <.icon name={TaskType.icon(@type)} class="size-3" /> {TaskType.label(@type)}
    </span>
    """
  end

  def poc_badge(assigns) do
    ~H"""
    <span
      class="inline-flex items-center rounded-md bg-warning/20 px-1.5 py-0.5 text-[11px] font-semibold text-warning-content"
      title="Built with /poc: requirements and code have not been reviewed"
    >
      POC
    </span>
    """
  end

  attr :presence, :atom, required: true

  def presence_dot(assigns) do
    ~H"""
    <span class="relative inline-flex size-2.5 shrink-0" title={to_string(@presence)}>
      <span
        :if={@presence == :working}
        class="absolute inline-flex size-full animate-ping rounded-full bg-sky-400 opacity-60"
      />
      <span class={[
        "relative inline-flex size-2.5 rounded-full",
        case @presence do
          :working -> "bg-sky-500"
          :idle -> "bg-amber-400"
          :away -> "bg-base-300"
          :ended -> "bg-base-300"
        end
      ]} />
    </span>
    """
  end

  @doc "What a session's presence means for the human."
  def presence_label(:working), do: "working"
  def presence_label(:idle), do: "waiting for you"
  def presence_label(:away), do: "away"
  def presence_label(:ended), do: "ended"

  def session_name(%AgentSession{name: name}) when is_binary(name) and name != "", do: name
  def session_name(%AgentSession{pi_session_id: id}), do: "session " <> String.slice(id, 0, 8)

  def worktree_label(nil), do: nil
  def worktree_label(%Worktree{} = worktree), do: Worktree.label(worktree)

  attr :worktree, Worktree, default: nil

  def worktree_chip(assigns) do
    ~H"""
    <span
      :if={@worktree}
      class="inline-flex max-w-56 items-center gap-1 truncate rounded-md bg-base-200 px-1.5 py-0.5 font-mono text-[11px] text-base-content/70"
      title={worktree_label(@worktree)}
    >
      <.icon name="hero-code-bracket-mini" class="size-3 shrink-0" />
      <span class="truncate">{@worktree.name}<span :if={@worktree.branch} class="text-base-content/40">@{@worktree.branch}</span></span>
    </span>
    """
  end

  attr :text, :string, default: nil
  attr :empty, :string, default: nil
  attr :class, :any, default: nil

  @doc "Renders agent-written markdown; raw HTML in it is dropped, never rendered."
  def markdown(assigns) do
    ~H"""
    <%= if @text in [nil, ""] do %>
      <p :if={@empty} class="text-sm italic text-base-content/40">{@empty}</p>
    <% else %>
      <div class={["md", @class]}>{Phoenix.HTML.raw(to_html(@text))}</div>
    <% end %>
    """
  end

  defp to_html(text) do
    MDEx.to_html!(text,
      extension: [table: true, tasklist: true, strikethrough: true, autolink: true],
      render: [unsafe: false]
    )
  end

  attr :at, DateTime, required: true
  attr :now, DateTime, required: true

  def time_ago(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@at)} title={Calendar.strftime(@at, "%Y-%m-%d %H:%M UTC")}>
      {ago(DateTime.diff(@now, @at))}
    </time>
    """
  end

  defp ago(s) when s < 45, do: "just now"
  defp ago(s) when s < 3600, do: "#{div(s, 60) |> max(1)}m ago"
  defp ago(s) when s < 86_400, do: "#{div(s, 3600)}h ago"
  defp ago(s), do: "#{div(s, 86_400)}d ago"

  attr :sessions, :list, required: true
  attr :now, DateTime, required: true

  @doc "The live agent sessions of a project: who is working where, and on what."
  def session_list(assigns) do
    ~H"""
    <ul id="sessions" class="space-y-1">
      <li :if={@sessions == []} class="px-2 py-3 text-sm text-base-content/50">
        No agent sessions in the last day.
      </li>
      <li
        :for={session <- @sessions}
        id={"session-#{session.id}"}
        class="rounded-lg px-2 py-2 transition hover:bg-base-200"
      >
        <% presence = AgentSession.presence(session, @now) %>
        <div class="flex items-center gap-2">
          <.presence_dot presence={presence} />
          <span class={[
            "truncate text-sm font-medium",
            presence in [:away, :ended] && "text-base-content/50"
          ]}>
            {session_name(session)}
          </span>
          <span class="ml-auto shrink-0 text-xs text-base-content/50">
            {presence_label(presence)}
          </span>
        </div>
        <div class="mt-1 flex flex-wrap items-center gap-1.5 pl-4.5 text-xs text-base-content/60">
          <span class="rounded-md bg-base-200 px-1.5 py-0.5 font-mono text-[10px] uppercase">
            {session.agent}
          </span>
          <.worktree_chip worktree={session.worktree} />
          <.link
            :if={session.task}
            navigate={
              ~p"/projects/#{session.project_id}/goals/#{session.task.goal.number}/tasks/#{session.task.number}"
            }
            class="truncate hover:underline"
          >
            Task {session.task.goal.number}.{session.task.number}: {session.task.title}
          </.link>
          <span class="ml-auto"><.time_ago at={session.last_seen_at} now={@now} /></span>
        </div>
      </li>
    </ul>
    """
  end

  attr :comments, :list, required: true
  attr :now, DateTime, required: true

  def comment_thread(assigns) do
    ~H"""
    <ol id="comments" class="space-y-3">
      <li :if={@comments == []} class="text-sm text-base-content/50">
        No comments yet. Comments you write here reach the agents working on this at the start of their next turn.
      </li>
      <li :for={comment <- @comments} id={"comment-#{comment.id}"} class="flex gap-3">
        <span class={[
          "grid size-7 shrink-0 place-items-center rounded-full text-xs",
          if(comment.author == :human,
            do: "bg-base-content text-base-100",
            else: "bg-sky-500/15 text-sky-700 dark:text-sky-300"
          )
        ]}>
          <.icon
            name={if comment.author == :human, do: "hero-user-mini", else: "hero-cpu-chip-mini"}
            class="size-4"
          />
        </span>
        <div class="min-w-0 flex-1 rounded-xl bg-base-200/60 px-3 py-2">
          <div class="mb-1 flex items-center gap-2 text-xs text-base-content/60">
            <span class="font-medium text-base-content/80">
              {if comment.author == :human, do: "You", else: agent_name(comment)}
            </span>
            <.time_ago at={comment.inserted_at} now={@now} />
          </div>
          <.markdown text={comment.body} class="text-sm" />
        </div>
      </li>
    </ol>
    """
  end

  defp agent_name(%{agent_session: %AgentSession{} = session}), do: session_name(session)
  defp agent_name(_comment), do: "Agent"

  attr :form, Phoenix.HTML.Form, required: true

  def comment_form(assigns) do
    ~H"""
    <.form for={@form} id="comment-form" phx-submit="comment" class="mt-4">
      <textarea
        id={@form[:body].id}
        name={@form[:body].name}
        rows="3"
        placeholder="Leave a note for the agents… (markdown)"
        class="w-full rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-sm outline-none transition focus:border-base-content/40 focus:ring-4 focus:ring-base-content/5"
        phx-debounce="blur"
      >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
      <div class="mt-2 flex justify-end">
        <button
          type="submit"
          id="comment-submit"
          class="rounded-lg bg-base-content px-3 py-1.5 text-sm font-medium text-base-100 transition hover:opacity-85 active:scale-[0.98] phx-submit-loading:opacity-50"
        >
          Comment
        </button>
      </div>
    </.form>
    """
  end

  attr :title, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block, required: true
  slot :actions

  def panel(assigns) do
    ~H"""
    <section id={@id} class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
      <div class="mb-3 flex items-center justify-between gap-2">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">{@title}</h2>
        {render_slot(@actions)}
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end
end
