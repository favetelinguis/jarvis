defmodule JarvisWeb.PlanningComponents do
  @moduledoc "Building blocks shared by the project, goal, and task pages."
  use JarvisWeb, :verified_routes
  use Phoenix.Component

  import JarvisWeb.CoreComponents, only: [icon: 1]

  alias Jarvis.Planning.TaskType
  alias Jarvis.Workspaces.{AgentSession, Worktree}

  attr :form, :atom, required: true
  attr :id, :string, default: nil

  @doc "The Diátaxis form of a page or section, as a word (never only a color)."
  def form_badge(assigns) do
    ~H"""
    <span
      id={@id}
      data-form={@form}
      title={JarvisWeb.Diataxis.purpose(@form)}
      class="inline-flex items-center rounded-md border border-base-content/30 px-1.5 py-0.5 text-[0.6875rem] font-medium normal-case tracking-normal text-base-content/80"
    >
      {JarvisWeb.Diataxis.label(@form)}
    </span>
    """
  end

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
    <span class="inline-flex items-center gap-1 rounded-md bg-base-200 px-1.5 py-0.5 text-[0.6875rem] font-medium text-base-content/70">
      <.icon name={TaskType.icon(@type)} class="size-3" /> {TaskType.label(@type)}
    </span>
    """
  end

  def poc_badge(assigns) do
    ~H"""
    <span
      class="inline-flex items-center rounded-md bg-warning/30 px-1.5 py-0.5 text-[0.6875rem] font-semibold text-base-content"
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
      class="inline-flex max-w-56 items-center gap-1 truncate rounded-md bg-base-200 px-1.5 py-0.5 font-mono text-[0.6875rem] text-base-content/70"
      title={worktree_label(@worktree)}
    >
      <.icon name="hero-code-bracket-mini" class="size-3 shrink-0" />
      <span class="truncate">{@worktree.name}<span :if={@worktree.branch} class="text-base-content/70">@{@worktree.branch}</span></span>
    </span>
    """
  end

  attr :text, :string, default: nil
  attr :empty, :string, default: nil
  attr :class, :any, default: nil

  attr :glossary, :list,
    default: [],
    doc:
      "`{pattern, meaning}` pairs from `WidgetComponents.glossary/2`; the first use of each term becomes a button that shows its meaning in place"

  @doc "Renders agent-written markdown; raw HTML in it is dropped, never rendered."
  def markdown(assigns) do
    ~H"""
    <%= if @text in [nil, ""] do %>
      <p :if={@empty} class="text-sm italic text-base-content/70">{@empty}</p>
    <% else %>
      <div class={["md", @class]}>
        {Phoenix.HTML.raw(@text |> to_html() |> link_terms(@glossary))}
      </div>
    <% end %>
    """
  end

  # Wraps the first use of each glossary term in text (never inside code, pre,
  # links, or buttons) in a button that toggles the meaning right after it.
  defp link_terms(html, []), do: html

  defp link_terms(html, glossary) do
    {parts, _depth, _left} =
      ~r/(<[^>]+>)/
      |> Regex.split(html, include_captures: true)
      |> Enum.reduce({[], 0, glossary}, fn
        "<" <> _ = tag, {acc, depth, left} ->
          {[tag | acc], depth + skip_delta(tag), left}

        text, {acc, 0, left} when left != [] ->
          {text, left} = wrap_terms(text, left)
          {[text | acc], 0, left}

        text, {acc, depth, left} ->
          {[text | acc], depth, left}
      end)

    parts |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp skip_delta(tag) do
    cond do
      Regex.match?(~r/^<(code|pre|a|button)[\s>]/, tag) -> 1
      Regex.match?(~r/^<\/(code|pre|a|button)>/, tag) -> -1
      true -> 0
    end
  end

  # Placeholders keep a later term from matching inside an earlier term's markup.
  defp wrap_terms(text, terms) do
    {text, left, found} =
      terms
      |> Enum.with_index()
      |> Enum.reduce({text, [], []}, fn {{pattern, meaning} = entry, i}, {text, left, found} ->
        case Regex.split(pattern, text, parts: 2, include_captures: true) do
          [before, match, rest] ->
            {before <> <<0xE000 + i::utf8>> <> rest, left,
             [{<<0xE000 + i::utf8>>, term_html(match, meaning)} | found]}

          _ ->
            {text, left ++ [entry], found}
        end
      end)

    {Enum.reduce(found, text, fn {mark, html}, text -> String.replace(text, mark, html) end),
     left}
  end

  defp term_html(match, meaning) do
    meaning = meaning |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    ~s(<button type="button" class="term" data-term aria-expanded="false">#{match}</button>) <>
      ~s(<span class="term-def" role="note" hidden>#{meaning}</span>)
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
      <li :if={@sessions == []} class="px-2 py-3 text-sm text-base-content/70">
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
            presence in [:away, :ended] && "text-base-content/70"
          ]}>
            {session_name(session)}
          </span>
          <span class="ml-auto shrink-0 text-xs text-base-content/70">
            {presence_label(presence)}
          </span>
        </div>
        <div class="mt-1 flex flex-wrap items-center gap-1.5 pl-4.5 text-xs text-base-content/70">
          <span class="rounded-md bg-base-200 px-1.5 py-0.5 font-mono text-[0.625rem] uppercase">
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
      <li :if={@comments == []} class="text-sm text-base-content/70">
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
          <div class="mb-1 flex items-center gap-2 text-xs text-base-content/70">
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
    field = assigns.form[:body]
    assigns = assign(assigns, field: field, errors: Enum.map(field.errors, &comment_error/1))

    ~H"""
    <.form for={@form} id="comment-form" phx-submit="comment" phx-hook="Draft" class="mt-4">
      <label for={@field.id} class="text-sm font-medium">Your comment (required)</label>
      <textarea
        id={@field.id}
        name={@field.name}
        required
        aria-invalid={@errors != [] && "true"}
        aria-describedby={@errors != [] && "#{@field.id}-error"}
        rows="3"
        placeholder="Leave a note for the agents… (markdown)"
        class="w-full rounded-xl border border-base-300 bg-base-100 px-3 py-2 text-sm outline-none transition focus:border-base-content/40 focus:ring-4 focus:ring-base-content/5"
        phx-debounce="blur"
      >{Phoenix.HTML.Form.normalize_value("textarea", @field.value)}</textarea>
      <p :if={@errors != []} id={"#{@field.id}-error"} class="mt-1 text-sm text-error">
        {Enum.join(@errors, " ")}
      </p>
      <div class="mt-2 flex justify-end">
        <button
          type="submit"
          id="comment-submit"
          class="rounded-lg bg-base-content px-3 py-1.5 text-sm font-medium text-base-100 transition hover:opacity-85 active:scale-[0.98] phx-submit-loading:opacity-50"
        >
          Send comment
        </button>
      </div>
    </.form>
    """
  end

  defp comment_error({_, opts}) do
    case opts[:validation] do
      :required -> "The comment is empty. Write some text, then send it."
      :length -> "The comment is too long. Shorten it to #{opts[:count]} characters or fewer."
      _ -> "The comment could not be sent. Change the text, then send it again."
    end
  end

  attr :title, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block, required: true
  slot :actions

  def panel(assigns) do
    ~H"""
    <section id={@id} class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm">
      <div class="mb-3 flex items-center justify-between gap-2">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-base-content/70">{@title}</h2>
        {render_slot(@actions)}
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end
end
