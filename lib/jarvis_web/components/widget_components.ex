defmodule JarvisWeb.WidgetComponents do
  @moduledoc """
  The design system: one component per widget kind, the frame every widget sits
  in, and the pieces around them (sections, threads, the lifecycle graph).

  Every widget and every part of one carries a comment button; a comment names
  its anchor, so the listening agent knows exactly what the human pointed at.
  Everything interactive sends `widget:*` events, handled by `JarvisWeb.WidgetEvents`.

  Colors come only from the theme tokens (`primary`, `secondary`, `accent`,
  `base-*`), so changing the brand colors restyles every widget.
  """
  use Phoenix.Component

  import JarvisWeb.CoreComponents, only: [icon: 1]
  import JarvisWeb.PlanningComponents, only: [form_badge: 1, markdown: 1, time_ago: 1]

  alias Jarvis.Planning
  alias Jarvis.Planning.{Catalog, TaskType}
  alias JarvisWeb.GraphLayout
  alias Phoenix.LiveView.JS

  ## Sections

  attr :sections, :list, required: true, doc: "`{key, label, recommended kinds}`"
  attr :widgets, :list, required: true
  attr :ctx, :map, required: true
  attr :prefix, :string, default: "section"
  attr :type, :atom, required: true, doc: "`:goal` or the task type; decides each section's form"

  @doc "The sections of a goal or task, each with its widgets in order and its Diátaxis form."
  def sections(assigns) do
    ~H"""
    <section
      :for={{key, label, recommended} <- @sections}
      id={"#{@prefix}-#{key}"}
      class="space-y-3"
    >
      <h2 class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wider text-base-content/70">
        <span class="h-3 w-1 rounded-full bg-primary" /> {label}
        <.form_badge
          id={"#{@prefix}-#{key}-form"}
          form={JarvisWeb.Diataxis.section(@type, key)}
        />
      </h2>
      <% in_section = Enum.filter(@widgets, &(&1.section == key)) %>
      <p
        :if={in_section == []}
        class="rounded-xl border border-dashed border-base-300 px-4 py-3 text-sm italic text-base-content/70"
      >
        Nothing here yet. Agents fill this with: {Enum.join(recommended, ", ")}.
      </p>
      <.widget :for={w <- in_section} w={w} ctx={@ctx} />
    </section>
    """
  end

  attr :sections, :list, required: true
  attr :widgets, :list, required: true
  attr :type, :atom, required: true
  attr :current, :string, required: true
  attr :path, :string, required: true, doc: "the page; each entry patches `?section=key` onto it"

  @doc """
  The contents of a task: every section with its number of widgets and its
  Diátaxis form. The page shows one section at a time, the current one.
  """
  def section_toc(assigns) do
    ~H"""
    <nav
      id="section-toc"
      aria-label="Sections"
      class="rounded-2xl border border-base-300 bg-base-100 p-3"
    >
      <h2 class="px-1 text-sm font-semibold">Sections</h2>
      <ol class="mt-2 grid gap-1 sm:grid-cols-2 xl:grid-cols-3">
        <li :for={{key, label, _} <- @sections}>
          <% count = Enum.count(@widgets, &(&1.section == key)) %>
          <.link
            id={"toc-#{key}"}
            patch={"#{@path}?section=#{key}"}
            aria-current={if key == @current, do: "true"}
            class={[
              "flex min-h-11 flex-wrap items-center gap-2 rounded-lg px-2 py-1 text-sm transition hover:bg-base-200",
              key == @current && "bg-base-200 font-semibold ring-2 ring-base-content"
            ]}
          >
            <span>{label}</span>
            <span class="text-base-content/70">
              {count} {if count == 1, do: "widget", else: "widgets"}
            </span>
            <.form_badge form={JarvisWeb.Diataxis.section(@type, key)} />
          </.link>
        </li>
      </ol>
    </nav>
    """
  end

  ## The frame

  attr :w, :map, required: true
  attr :ctx, :map, required: true

  def widget(assigns) do
    assigns =
      assign(assigns,
        thread: thread_groups(assigns.ctx.comments, assigns.w),
        composing?: composing?(assigns.ctx, assigns.w),
        total:
          Enum.count(assigns.ctx.comments, &(&1.widget_id == assigns.w.id and &1.part == nil))
      )

    assigns = assign(assigns, :changed?, MapSet.member?(assigns.ctx.changed, assigns.w.id))

    ~H"""
    <article
      id={"widget-#{@w.id}"}
      data-changed={to_string(@changed?)}
      class={[
        "group/widget group/part rounded-2xl border bg-base-100 shadow-sm transition hover:border-primary/40",
        if(@changed?, do: "border-2 border-dashed border-base-content/70", else: "border-base-300")
      ]}
    >
      <header class="flex flex-wrap items-center gap-2 px-4 pt-3 text-xs text-base-content/70">
        <span class="font-medium">{Catalog.label(@w.kind)}</span>
        <span class="font-mono text-base-content/70">W{@w.id}</span>
        <span
          :if={@changed?}
          id={"changed-#{@w.id}"}
          class="inline-flex items-center gap-1 rounded-md bg-base-content px-1.5 py-0.5 font-semibold text-base-100"
        >
          Updated by an agent
          <button
            type="button"
            phx-click="widget:seen"
            phx-value-widget={@w.id}
            class="underline"
          >
            Mark as read
          </button>
        </span>
        <span class="ml-auto" />
        <.part_button w={@w} ctx={@ctx} />
      </header>
      <div class="px-4 pb-4 pt-2">
        <.body w={@w} ctx={@ctx} />
      </div>

      <details :if={@ctx.sandbox} class="border-t border-base-200 px-4 py-2 text-xs">
        <summary class="cursor-pointer select-none font-medium text-base-content/70">
          What the agent sees and writes
        </summary>
        <p class="mt-2 text-base-content/70">
          The agent writes this data with <code>jarvis_widgets</code>, and reads the text below.
        </p>
        <pre class="mt-2 overflow-x-auto rounded-lg bg-base-200 p-3 font-mono text-[0.6875rem] leading-relaxed">{Jason.encode!(@w.data, pretty: true)}</pre>
        <pre class="mt-2 overflow-x-auto whitespace-pre-wrap rounded-lg bg-base-200 p-3 font-mono text-[0.6875rem] leading-relaxed">{Catalog.text(@w)}</pre>
      </details>

      <div
        :if={@thread != [] or @composing?}
        class="space-y-3 border-t border-base-200 bg-base-200/40 px-4 py-3 rounded-b-2xl"
      >
        <.thread :for={group <- @thread} group={group} w={@w} ctx={@ctx} />
        <.composer :if={@composing?} w={@w} ctx={@ctx} />
      </div>
    </article>
    """
  end

  defp composing?(%{composer: %{widget: id}}, %{id: id}), do: true
  defp composing?(_ctx, _w), do: false

  defp thread_groups(comments, w) do
    comments
    |> Enum.filter(&(&1.widget_id == w.id))
    |> Enum.group_by(& &1.part)
    |> Enum.sort_by(fn {_, [first | _]} -> first.id end)
    |> Enum.map(fn {part, items} ->
      gone? = part != nil and Catalog.part(w, part) == nil
      %{part: part, comments: items, gone?: gone?, label: hd(items).anchor_label}
    end)
  end

  attr :w, :map, required: true
  attr :part, :string, default: nil
  attr :ctx, :map, required: true

  @doc "The comment button of a widget or one of its parts; shows how many comments it has."
  def part_button(assigns) do
    count =
      Enum.count(
        assigns.ctx.comments,
        &(&1.widget_id == assigns.w.id and &1.part == assigns.part)
      )

    assigns = assign(assigns, :count, count)

    ~H"""
    <button
      id={comment_button_id(@w.id, @part)}
      type="button"
      phx-click="widget:compose"
      phx-value-widget={@w.id}
      phx-value-part={@part}
      aria-label={if @part, do: "Comment on #{@part}", else: "Comment on this widget"}
      title={if @part, do: "Comment on #{@part}", else: "Comment on this widget"}
      class="inline-flex shrink-0 items-center gap-1 rounded-md px-1.5 py-0.5 text-[0.6875rem] font-medium text-base-content/70 transition hover:bg-primary/10 hover:text-primary"
    >
      <.icon name="hero-chat-bubble-left-ellipsis-mini" class="size-3.5" />
      <span aria-hidden="true">Comment</span>
      <span :if={@count > 0}>({@count})</span>
    </button>
    """
  end

  attr :group, :map, required: true
  attr :w, :map, required: true
  attr :ctx, :map, required: true

  defp thread(assigns) do
    last = List.last(assigns.group.comments)

    assigns =
      assign(assigns,
        waiting?: last.author == :human and last.deliver and is_nil(last.delivered_at)
      )

    ~H"""
    <div id={"thread-#{@w.id}-#{@group.part || "widget"}"} class="space-y-2">
      <p class="flex items-center gap-2 text-[0.6875rem] font-medium text-base-content/70">
        <.icon name="hero-chat-bubble-left-right-mini" class="size-3.5" />
        {@group.label}
        <span
          :if={@group.gone?}
          class="rounded bg-warning/20 px-1.5 py-0.5 text-[0.625rem] font-semibold uppercase text-base-content/70"
        >
          Part removed
        </span>
      </p>
      <ol class="space-y-2">
        <li :for={c <- @group.comments} id={"comment-#{c.id}"} class="flex gap-2">
          <span class={[
            "mt-0.5 grid size-5 shrink-0 place-items-center rounded-full",
            case c.author do
              :human -> "bg-base-content text-base-100"
              :agent -> "bg-primary text-primary-content"
              :system -> "bg-base-300 text-base-content/70"
            end
          ]}>
            <.icon
              name={
                case c.author do
                  :human -> "hero-user-mini"
                  :agent -> "hero-cpu-chip-mini"
                  :system -> "hero-bolt-mini"
                end
              }
              class="size-3"
            />
          </span>
          <div class={[
            "min-w-0 flex-1 text-sm",
            c.author == :system && "italic text-base-content/70"
          ]}>
            <.markdown glossary={@ctx.glossary} text={c.body} class="text-sm" />
            <span class="text-[0.6875rem] text-base-content/70">
              <.time_ago at={c.inserted_at} now={@ctx.now} />
            </span>
          </div>
        </li>
      </ol>
      <p
        :if={@waiting?}
        id={"thread-status-#{@w.id}-#{@group.part || "widget"}"}
        class={[
          "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[0.6875rem] font-medium",
          if(@ctx.listening,
            do: "bg-primary/10 text-primary",
            else: "bg-warning/20 text-base-content/70"
          )
        ]}
      >
        <.icon
          name={if @ctx.listening, do: "hero-signal-mini", else: "hero-signal-slash-mini"}
          class="size-3.5"
        />
        {cond do
          @ctx.listening == :next_turn -> "Will be delivered at the session's next turn"
          @ctx.listening -> "The agent is being woken…"
          true -> "No agent listening"
        end}
      </p>
    </div>
    """
  end

  attr :w, :map, required: true
  attr :ctx, :map, required: true

  defp composer(assigns) do
    %{w: w, ctx: %{composer: %{part: part}}} = assigns

    assigns =
      assign(assigns,
        label: Planning.anchor_label(w, part),
        # Sending or cancelling hands focus back to the button that opened it.
        opener: comment_button_id(w.id, part)
      )

    ~H"""
    <form
      id={"composer-#{@w.id}"}
      phx-submit={JS.push("widget:comment") |> JS.focus(to: "#" <> @opener)}
      phx-hook="Draft"
      data-draft-key={"composer-#{@w.id}-#{@ctx.composer.part}"}
      class="space-y-2"
    >
      <label for={"composer-body-#{@w.id}"} class="text-[0.6875rem] font-medium text-base-content/70">
        Commenting on {@label} (required)
      </label>
      <textarea
        id={"composer-body-#{@w.id}"}
        name="body"
        rows="2"
        required
        phx-mounted={JS.focus()}
        placeholder="Ask a question, or tell the agent what to change here…"
        class="w-full rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm outline-none focus:border-primary focus:ring-4 focus:ring-primary/10"
      />
      <div class="flex justify-end gap-2">
        <button
          type="button"
          phx-click={JS.push("widget:cancel") |> JS.focus(to: "#" <> @opener)}
          class="rounded-lg px-3 py-1.5 text-sm text-base-content/70 hover:bg-base-200"
        >
          Cancel
        </button>
        <button
          type="submit"
          class="rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-primary-content transition hover:opacity-90 active:scale-[0.98]"
        >
          Send comment
        </button>
      </div>
    </form>
    """
  end

  attr :comments, :list, required: true

  @doc "Comments whose widget was deleted, with the anchor as it was."
  def removed_anchors(assigns) do
    ~H"""
    <section
      :if={@comments != []}
      id="removed-anchors"
      class="rounded-2xl border border-dashed border-base-300 p-4"
    >
      <h2 class="text-xs font-semibold uppercase tracking-wider text-base-content/70">
        Removed anchors
      </h2>
      <ul class="mt-2 space-y-3">
        <li :for={c <- @comments} id={"removed-#{c.id}"} class="text-sm">
          <p class="flex items-center gap-2 text-[0.6875rem] font-medium text-base-content/70">
            {c.anchor_label}
            <span class="rounded bg-warning/20 px-1.5 py-0.5 text-[0.625rem] font-semibold uppercase">
              Widget removed
            </span>
          </p>
          <blockquote
            :if={c.anchor_text}
            class="mt-1 border-l-2 border-base-300 pl-2 text-xs text-base-content/70"
          >
            {String.slice(c.anchor_text, 0, 240)}
          </blockquote>
          <p class="mt-1">{c.body}</p>
        </li>
      </ul>
    </section>
    """
  end

  ## Bodies

  attr :w, :map, required: true
  attr :ctx, :map, required: true

  defp body(%{w: %{kind: "prose"}} = assigns) do
    ~H"""
    <.markdown glossary={@ctx.glossary} text={@w.data["text"]} />
    """
  end

  defp body(%{w: %{kind: "callout"}} = assigns) do
    {icon, style, tone} =
      case assigns.w.data["tone"] do
        "info" -> {"hero-information-circle", "border-info/60 bg-info/10", "Info"}
        "warning" -> {"hero-exclamation-triangle", "border-warning/70 bg-warning/10", "Warning"}
        "risk" -> {"hero-shield-exclamation", "border-error/60 bg-error/10", "Risk"}
      end

    assigns = assign(assigns, icon: icon, style: style, tone: tone)

    ~H"""
    <div class={["flex gap-3 rounded-xl border-l-4 px-4 py-3", @style]}>
      <.icon name={@icon} class="mt-0.5 size-5 shrink-0" />
      <div class="min-w-0">
        <p class="text-[0.6875rem] font-semibold uppercase tracking-wide">{@tone}</p>
        <p class="font-semibold">{@w.data["title"]}</p>
        <.markdown
          :if={@w.data["body"]}
          glossary={@ctx.glossary}
          text={@w.data["body"]}
          class="mt-1 text-sm"
        />
      </div>
    </div>
    """
  end

  @pattern_style %{
    "ubiquitous" => "bg-slate-500/15 text-slate-800 dark:text-slate-100",
    "event" => "bg-sky-500/15 text-sky-900 dark:text-sky-100",
    "state" => "bg-violet-500/15 text-violet-900 dark:text-violet-100",
    "unwanted" => "bg-rose-500/15 text-rose-900 dark:text-rose-100",
    "optional" => "bg-amber-500/20 text-amber-900 dark:text-amber-100"
  }

  defp body(%{w: %{kind: "requirement"}} = assigns) do
    d = assigns.w.data

    assigns =
      assign(assigns,
        d: d,
        confirmed?: assigns.w.human["confirmed"] == true,
        style: Map.fetch!(@pattern_style, d["pattern"]),
        keyword: Catalog.pattern_keyword(d["pattern"])
      )

    ~H"""
    <div class={[
      "rounded-xl p-3 ring-1 ring-inset transition",
      if(@confirmed?, do: "bg-success/10 ring-success/50", else: "bg-base-200/50 ring-base-300")
    ]}>
      <div class="flex flex-wrap items-center gap-2">
        <span class="rounded-md bg-base-content px-1.5 py-0.5 font-mono text-xs font-semibold text-base-100">
          {@d["id"]}
        </span>
        <span class={[
          "rounded-full px-2 py-0.5 text-[0.6875rem] font-semibold uppercase tracking-wide",
          @style
        ]}>
          {@d["pattern"]}
        </span>
        <span
          :if={@confirmed?}
          class="inline-flex items-center gap-1 text-xs font-medium text-success"
        >
          <.icon name="hero-check-circle-mini" class="size-4" /> Confirmed
        </span>
      </div>

      <div class="mt-3 flex flex-col items-stretch gap-2 text-sm md:flex-row md:items-center">
        <div
          :if={@keyword}
          class="min-w-0 flex-1 rounded-lg bg-base-100 px-3 py-2 ring-1 ring-base-300"
        >
          <p class={[
            "text-[0.625rem] font-bold uppercase tracking-wider",
            @style,
            "w-fit rounded px-1"
          ]}>
            {@keyword}
          </p>
          <p class="mt-1">{@d["trigger"]}</p>
        </div>
        <.icon
          :if={@keyword}
          name="hero-arrow-right"
          class="hidden size-4 shrink-0 text-base-content/70 md:block"
        />
        <div class="min-w-0 rounded-lg bg-base-100 px-3 py-2 ring-1 ring-base-300 md:w-40 md:max-w-[25%] md:shrink-0">
          <p class="text-[0.625rem] font-bold uppercase tracking-wider text-base-content/70">
            the system
          </p>
          <p class="mt-1 font-medium">{@d["system"]}</p>
        </div>
        <.icon name="hero-arrow-right" class="hidden size-4 shrink-0 text-base-content/70 md:block" />
        <div class="min-w-0 flex-1 rounded-lg bg-primary/10 px-3 py-2 ring-1 ring-primary/40">
          <p class="text-[0.625rem] font-bold uppercase tracking-wider text-primary">shall</p>
          <p class="mt-1">{@d["response"]}</p>
        </div>
      </div>

      <div class="mt-3 flex flex-wrap gap-2">
        <button
          type="button"
          id={"confirm-#{@w.id}"}
          phx-click="widget:action"
          phx-value-widget={@w.id}
          phx-value-action={if @confirmed?, do: "unconfirm", else: "confirm"}
          class={[
            "inline-flex items-center gap-1 rounded-lg px-3 py-1.5 text-sm font-medium transition active:scale-[0.98]",
            if(@confirmed?,
              do: "bg-success/15 text-base-content hover:bg-success/25",
              else: "bg-primary text-primary-content hover:opacity-90"
            )
          ]}
        >
          <.icon name="hero-check-mini" class="size-4" />
          {if @confirmed?, do: "Confirmed · undo", else: "Confirm"}
        </button>
        <button
          type="button"
          id={"question-#{@w.id}"}
          phx-click="widget:compose"
          phx-value-widget={@w.id}
          class="inline-flex items-center gap-1 rounded-lg border border-base-300 px-3 py-1.5 text-sm font-medium transition hover:bg-base-200"
        >
          <.icon name="hero-question-mark-circle-mini" class="size-4" /> Question
        </button>
      </div>
    </div>
    """
  end

  defp body(%{w: %{kind: "examples"}} = assigns) do
    d = assigns.w.data
    sel = (assigns.ctx.ui[assigns.w.id] || %{})["sel"] || %{}
    chosen = Enum.reject(sel, fn {_, v} -> v in [nil, ""] end)

    matches? = fn row ->
      Enum.all?(chosen, fn {i, v} -> Enum.at(row["values"], String.to_integer(i)) == v end)
    end

    assigns =
      assign(assigns,
        d: d,
        sel: sel,
        chosen: chosen,
        matches?: matches?,
        none?: chosen != [] and not Enum.any?(d["rows"], matches?)
      )

    ~H"""
    <div>
      <p :if={@d["title"]} class="mb-2 font-semibold">{@d["title"]}</p>
      <form
        id={"examples-#{@w.id}"}
        phx-change="widget:select"
        class="mb-3 flex flex-wrap items-end gap-3 rounded-xl bg-base-200/50 p-3"
      >
        <input type="hidden" name="widget" value={@w.id} />
        <p class="w-full text-xs text-base-content/70">
          Pick values to find the example that covers them.
        </p>
        <label :for={{column, i} <- Enum.with_index(@d["columns"])} class="text-xs">
          <span class="mb-1 block font-medium text-base-content/70">{column}</span>
          <select
            name={"sel[#{i}]"}
            class="rounded-lg border border-base-300 bg-base-100 px-2 py-1 text-sm"
          >
            <option value="">any</option>
            <option
              :for={v <- Enum.uniq(for r <- @d["rows"], do: Enum.at(r["values"], i))}
              value={v}
              selected={@sel[to_string(i)] == v}
            >
              {v}
            </option>
          </select>
        </label>
        <button
          :if={@chosen != []}
          type="button"
          phx-click="widget:select_clear"
          phx-value-widget={@w.id}
          class="rounded-lg px-2 py-1 text-xs text-primary hover:bg-primary/10"
        >
          Clear
        </button>
      </form>

      <p
        :if={@none?}
        id={"examples-none-#{@w.id}"}
        class="mb-3 rounded-lg bg-warning/15 px-3 py-2 text-sm"
      >
        No example covers this combination: {Enum.map_join(Enum.sort(@chosen), ", ", fn {i, v} ->
          "#{Enum.at(@d["columns"], String.to_integer(i))} #{v}"
        end)}
      </p>

      <div class="overflow-x-auto rounded-xl ring-1 ring-base-300">
        <table class="w-full text-sm">
          <thead class="bg-base-200/70 text-left text-xs uppercase tracking-wide text-base-content/70">
            <tr>
              <th :for={c <- @d["columns"]} class="px-3 py-2 font-semibold">{c}</th>
              <th class="px-3 py-2 font-semibold">{@d["expected_label"] || "Expected"}</th>
              <th class="w-8" />
            </tr>
          </thead>
          <tbody>
            <tr
              :for={row <- @d["rows"]}
              id={"row-#{@w.id}-#{row["id"]}"}
              data-match={to_string(@chosen != [] and @matches?.(row))}
              class={[
                "group/part border-t border-base-200 transition",
                (@chosen != [] and @matches?.(row)) && "bg-primary/10",
                (@chosen != [] and not @matches?.(row)) && "opacity-40"
              ]}
            >
              <td :for={v <- row["values"]} class="px-3 py-2">{v}</td>
              <td class="px-3 py-2 font-medium">{row["expected"]}</td>
              <td class="px-1"><.part_button w={@w} part={"row:#{row["id"]}"} ctx={@ctx} /></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp body(%{w: %{kind: "glossary_term"}} = assigns) do
    ~H"""
    <div class="flex gap-3">
      <.icon name="hero-book-open" class="mt-1 size-5 shrink-0 text-primary" />
      <div class="min-w-0">
        <p class="text-lg font-semibold">{@w.data["term"]}</p>
        <.markdown glossary={@ctx.glossary} text={@w.data["meaning"]} class="text-sm" />
        <p :if={@w.data["limits"]} class="mt-2 text-sm text-base-content/70">
          <span class="font-semibold">Limits:</span> {@w.data["limits"]}
        </p>
      </div>
    </div>
    """
  end

  defp body(%{w: %{kind: "decision"}} = assigns) do
    ~H"""
    <div class="flex gap-3">
      <.icon name="hero-scale" class="mt-1 size-5 shrink-0 text-accent" />
      <div class="min-w-0">
        <p class="font-semibold">{@w.data["decision"]}</p>
        <.markdown glossary={@ctx.glossary} text={@w.data["reason"]} class="text-sm" />
        <div
          :if={(@w.data["alternatives"] || []) != []}
          class="mt-2 flex flex-wrap items-center gap-1.5 text-xs"
        >
          <span class="text-base-content/70">Rejected:</span>
          <span
            :for={a <- @w.data["alternatives"]}
            class="rounded-full bg-base-200 px-2 py-0.5 line-through decoration-base-content/40"
          >
            {a}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp body(%{w: %{kind: "diagram"}} = assigns) do
    error = assigns.w.human["error"]
    hash = :erlang.phash2(assigns.w.data["source"])
    assigns = assign(assigns, error: error, hash: hash)

    ~H"""
    <div>
      <p :if={@w.data["title"]} class="mb-2 font-semibold">{@w.data["title"]}</p>
      <div
        :if={@error}
        id={"diagram-error-#{@w.id}"}
        class="mb-2 rounded-lg border border-error/50 bg-error/10 p-3 text-sm"
      >
        <p class="font-semibold">This diagram could not be drawn</p>
        <p class="mt-1 font-mono text-xs">{@error}</p>
        <pre class="mt-2 overflow-x-auto rounded bg-base-200 p-2 font-mono text-xs">{@w.data["source"]}</pre>
      </div>
      <div
        id={"diagram-#{@w.id}-#{@hash}"}
        phx-hook="Mermaid"
        phx-update="ignore"
        data-widget={@w.id}
        data-source={@w.data["source"]}
        data-had-error={to_string(@error != nil)}
        class="overflow-x-auto rounded-xl bg-base-200/40 p-3 [&_svg]:mx-auto [&_svg]:max-w-full [&_.node]:cursor-pointer [&_.edgeLabel]:cursor-pointer"
      />
      <p class="mt-1 text-[0.6875rem] text-base-content/70">
        Click a node, edge, or message to comment on it.
      </p>
    </div>
    """
  end

  @node_style %{
    "person" => "rounded-full border-2 border-primary bg-primary/10",
    "service" => "rounded-xl border-2 border-primary bg-base-100",
    "component" => "rounded-md border-2 border-l-8 border-secondary bg-base-100",
    "datastore" => "rounded-[50%/22%] border-2 border-accent bg-accent/10",
    "queue" => "rounded-md border-2 border-double border-accent bg-base-100 border-4",
    "external" => "rounded-xl border-2 border-dashed border-base-content/50 bg-base-200"
  }
  defp body(%{w: %{kind: "architecture"}} = assigns) do
    d = assigns.w.data
    ui = assigns.ctx.ui[assigns.w.id] || %{}
    tour = d["tour"] || []
    index = parse_index(ui["tour"], length(tour))
    step = index && Enum.at(tour, index)
    layout = GraphLayout.architecture(d)
    selected = ui["sel"]

    lit_nodes = step && MapSet.new(step["nodes"] || [])
    lit_edges = step && MapSet.new(step["edges"] || [])

    assigns =
      assign(assigns,
        d: d,
        tour: tour,
        index: index,
        step: step,
        layout: layout,
        selected: selected,
        selected_part: selected && Catalog.part(assigns.w, selected),
        lit_nodes: lit_nodes,
        lit_edges: lit_edges,
        node_style: @node_style,
        detail_at: selected && detail_position(selected, layout)
      )

    ~H"""
    <div>
      <p :if={@d["title"]} class="mb-2 font-semibold">{@d["title"]}</p>
      <div class="grid gap-3 lg:grid-cols-[minmax(0,1fr)_16rem]">
        <div id={"arch-#{@w.id}"} phx-hook="PanZoom" class="relative">
          <div
            data-pz-viewport
            class="relative h-80 cursor-grab touch-none overflow-hidden rounded-xl bg-base-200/50 ring-1 ring-base-300 active:cursor-grabbing"
          >
            <div
              data-pz-stage
              data-w={@layout.width}
              data-h={@layout.height}
              class="absolute left-0 top-0 origin-top-left"
              style={"width: #{@layout.width}px; height: #{@layout.height}px"}
            >
              <div
                :for={g <- @layout.groups}
                id={"group-#{@w.id}-#{g.id}"}
                class="group/part absolute rounded-2xl border-2 border-dashed border-secondary/50 bg-secondary/5"
                style={"left: #{g.x}px; top: #{g.y}px; width: #{g.w}px; height: #{g.h}px"}
              >
                <button
                  type="button"
                  data-pz-no-pan
                  phx-click="widget:ui"
                  phx-value-widget={@w.id}
                  phx-value-key="sel"
                  phx-value-value={"group:#{g.id}"}
                  value={"group:#{g.id}"}
                  class="px-3 pt-1 text-[0.6875rem] font-semibold uppercase tracking-wide text-secondary"
                >
                  {g.label}
                </button>
              </div>

              <svg
                class="pointer-events-none absolute left-0 top-0"
                width={@layout.width}
                height={@layout.height}
                aria-hidden="true"
              >
                <defs>
                  <marker
                    id={"arrow-#{@w.id}"}
                    viewBox="0 0 10 10"
                    refX="9"
                    refY="5"
                    markerWidth="7"
                    markerHeight="7"
                    orient="auto-start-reverse"
                  >
                    <path d="M0,0 L10,5 L0,10 z" class="fill-secondary" />
                  </marker>
                </defs>
                <g :for={e <- @layout.edges}>
                  <path
                    d={e.d}
                    fill="none"
                    marker-end={"url(#arrow-#{@w.id})"}
                    class={[
                      "stroke-secondary transition",
                      @step && e.id not in @lit_edges && "opacity-20",
                      @step && e.id in @lit_edges && "!stroke-primary",
                      @selected == "edge:#{e.id}" && "!stroke-accent"
                    ]}
                    stroke-width={if @step && e.id in @lit_edges, do: 3, else: 2}
                  />
                  <path
                    d={e.d}
                    fill="none"
                    stroke="transparent"
                    stroke-width="14"
                    class="pointer-events-auto cursor-pointer"
                    phx-click="widget:ui"
                    phx-value-widget={@w.id}
                    phx-value-key="sel"
                    phx-value-value={"edge:#{e.id}"}
                    data-pz-no-pan
                  />
                  <text
                    :if={e.label}
                    x={e.lx}
                    y={e.ly - 5}
                    text-anchor="middle"
                    class="fill-base-content text-[0.6875rem]"
                    paint-order="stroke"
                    stroke-width="4"
                    style="stroke: var(--color-base-100)"
                  >
                    {e.label}
                  </text>
                </g>
              </svg>

              <button
                :for={n <- @d["nodes"]}
                type="button"
                id={"node-#{@w.id}-#{n["id"]}"}
                data-pz-no-pan
                phx-click="widget:ui"
                phx-value-widget={@w.id}
                phx-value-key="sel"
                phx-value-value={"node:#{n["id"]}"}
                value={"node:#{n["id"]}"}
                class={[
                  "absolute flex items-center gap-2 px-3 text-left text-sm font-medium shadow-sm transition hover:shadow-md",
                  @node_style[n["kind"]],
                  @step && n["id"] not in @lit_nodes && "opacity-25",
                  @step && n["id"] in @lit_nodes && "ring-4 ring-primary/40",
                  @selected == "node:#{n["id"]}" && "ring-4 ring-accent/60"
                ]}
                style={node_style(@layout.nodes[n["id"]])}
              >
                <span class="min-w-0">
                  <span class="block truncate">{n["label"]}</span>
                  <span class="block text-[0.625rem] font-normal uppercase tracking-wide text-base-content/70">{n[
                    "kind"
                  ]}</span>
                </span>
              </button>

              <div
                :if={@selected_part && @detail_at}
                id={"detail-#{@w.id}"}
                data-pz-no-pan
                role="note"
                class="absolute z-10 w-64 cursor-auto rounded-xl border-2 border-base-content bg-base-100 p-3 text-sm shadow-lg"
                style={"left: #{elem(@detail_at, 0)}px; top: #{elem(@detail_at, 1)}px"}
              >
                <% {label, text} = @selected_part %>
                <p class="text-[0.6875rem] font-semibold uppercase tracking-wide text-base-content/70">
                  {label}
                </p>
                <p class="mt-1 whitespace-pre-wrap">{text}</p>
                <div class="mt-2 flex flex-wrap gap-2">
                  <button
                    type="button"
                    phx-click="widget:compose"
                    phx-value-widget={@w.id}
                    phx-value-part={@selected}
                    class="inline-flex items-center gap-1 rounded-lg border border-base-300 px-2.5 py-1 text-xs font-medium hover:bg-base-200"
                  >
                    <.icon name="hero-chat-bubble-left-ellipsis-mini" class="size-3.5" />
                    Comment on this
                  </button>
                  <button
                    type="button"
                    phx-click="widget:ui"
                    phx-value-widget={@w.id}
                    phx-value-key="sel"
                    phx-value-value=""
                    value=""
                    class="rounded-lg px-2.5 py-1 text-xs font-medium hover:bg-base-200"
                  >
                    Close
                  </button>
                </div>
              </div>
            </div>
          </div>
          <div class="absolute right-2 top-2 flex flex-col gap-1">
            <button
              type="button"
              data-pz="in"
              class="rounded-md bg-base-100 px-2 py-1 text-xs font-medium shadow ring-1 ring-base-300 hover:bg-base-200"
            >Zoom in</button>
            <button
              type="button"
              data-pz="out"
              class="rounded-md bg-base-100 px-2 py-1 text-xs font-medium shadow ring-1 ring-base-300 hover:bg-base-200"
            >Zoom out</button>
            <button
              type="button"
              data-pz="fit"
              class="rounded-md bg-base-100 px-2 py-1 text-xs font-medium shadow ring-1 ring-base-300 hover:bg-base-200"
            >Fit</button>
          </div>
        </div>

        <aside class="space-y-3 text-sm">
          <div
            :if={@tour != []}
            id={"tour-#{@w.id}"}
            tabindex="-1"
            class="rounded-xl bg-base-200/60 p-3"
          >
            <%= if @step do %>
              <p class="text-[0.6875rem] font-semibold uppercase tracking-wide text-primary">
                Step {@index + 1} of {length(@tour)}
              </p>
              <p class="mt-1 font-semibold">{@step["title"]}</p>
              <.markdown glossary={@ctx.glossary} text={@step["narration"]} class="mt-1 text-sm" />
              <div class="mt-3 flex items-center gap-2">
                <button
                  :if={@index > 0}
                  id={"tour-prev-#{@w.id}"}
                  type="button"
                  phx-click={JS.push("widget:ui") |> JS.focus(to: "#tour-#{@w.id}")}
                  phx-value-widget={@w.id}
                  phx-value-key="tour"
                  phx-value-value={@index - 1}
                  value={@index - 1}
                  class="rounded-lg border border-base-300 px-2.5 py-1 text-xs font-medium hover:bg-base-100 disabled:opacity-40"
                >Previous</button>
                <button
                  :if={@index < length(@tour) - 1}
                  id={"tour-next-#{@w.id}"}
                  type="button"
                  phx-click={JS.push("widget:ui") |> JS.focus(to: "#tour-#{@w.id}")}
                  phx-value-widget={@w.id}
                  phx-value-key="tour"
                  phx-value-value={@index + 1}
                  value={@index + 1}
                  class="rounded-lg bg-primary px-2.5 py-1 text-xs font-medium text-primary-content hover:opacity-90 disabled:opacity-40"
                >Next</button>
                <button
                  id={"tour-end-#{@w.id}"}
                  type="button"
                  phx-click={JS.push("widget:ui") |> JS.focus(to: "#tour-#{@w.id}")}
                  phx-value-widget={@w.id}
                  phx-value-key="tour"
                  phx-value-value=""
                  value=""
                  class="ml-auto text-xs text-base-content/70 hover:underline"
                >End tour</button>
              </div>
            <% else %>
              <p class="font-semibold">Guided tour</p>
              <p class="mt-1 text-xs text-base-content/70">{length(@tour)} steps, at your pace.</p>
              <button
                id={"tour-start-#{@w.id}"}
                type="button"
                phx-click={JS.push("widget:ui") |> JS.focus(to: "#tour-#{@w.id}")}
                phx-value-widget={@w.id}
                phx-value-key="tour"
                phx-value-value="0"
                value="0"
                class="mt-2 rounded-lg bg-primary px-2.5 py-1 text-xs font-medium text-primary-content hover:opacity-90"
              >Start tour</button>
            <% end %>
          </div>

          <p class="rounded-xl bg-base-200/60 p-3 text-xs text-base-content/70">
            Click a node, group, or edge to read about it right there. Drag to pan, scroll to zoom.
          </p>
        </aside>
      </div>
    </div>
    """
  end

  defp body(%{w: %{kind: "quiz"}} = assigns) do
    d = assigns.w.data
    answers = assigns.w.human["answers"] || %{}
    answered = Enum.count(d["questions"], &Map.has_key?(answers, &1["id"]))
    correct = Enum.count(d["questions"], &(get_in(answers, [&1["id"], "correct"]) == true))

    total = length(d["questions"])
    index = parse_index((assigns.ctx.ui[assigns.w.id] || %{})["q"], total) || 0

    assigns =
      assign(assigns,
        d: d,
        answers: answers,
        answered: answered,
        correct: correct,
        total: total,
        index: index
      )

    ~H"""
    <div>
      <div class="mb-3 flex flex-wrap items-center gap-2 text-xs">
        <span class="rounded-full bg-accent/20 px-2 py-0.5 font-semibold uppercase tracking-wide">
          {String.replace(@d["mode"], "_", "-")}
        </span>
        <span class="text-base-content/70">
          {case @d["mode"] do
            "self_study" ->
              "Your answers stay in your browser session; the agent does not see them."

            "feedback" ->
              "Your answers are sent to the agent, so it can see what was unclear."

            "gate" ->
              "The transition “#{@d["gates"]}” waits until every question is answered correctly."
          end}
        </span>
        <span id={"quiz-progress-#{@w.id}"} class="ml-auto font-mono text-base-content/70">
          {@answered}/{@total} answered · {@correct} correct
        </span>
      </div>
      <div class="mb-3 h-1.5 overflow-hidden rounded-full bg-base-200">
        <div
          class="h-full bg-success transition-all"
          style={"width: #{@correct * 100 / max(@total, 1)}%"}
        />
      </div>

      <p :if={@total > 1} id={"quiz-step-#{@w.id}"} tabindex="-1" class="mb-2 text-sm font-semibold">
        Step {@index + 1} of {@total}
      </p>
      <ol class="space-y-4">
        <li
          :for={{q, n} <- Enum.with_index(@d["questions"], 1)}
          :if={n == @index + 1}
          id={"question-#{@w.id}-#{q["id"]}"}
          class="group/part rounded-xl bg-base-200/50 p-3"
        >
          <% a = @answers[q["id"]] %>
          <div class="flex items-start gap-2">
            <span class="font-mono text-xs text-base-content/70">{n}.</span>
            <div class="min-w-0 flex-1">
              <.markdown glossary={@ctx.glossary} text={q["prompt"]} class="font-medium" />
            </div>
            <.part_button w={@w} part={"question:#{q["id"]}"} ctx={@ctx} />
          </div>

          <form
            :if={q["type"] != "text"}
            id={"answer-#{@w.id}-#{q["id"]}"}
            phx-submit="widget:answer"
            phx-hook="Draft"
            class="mt-2 space-y-1.5"
          >
            <input type="hidden" name="widget" value={@w.id} />
            <input type="hidden" name="question" value={q["id"]} />
            <label
              :for={o <- q["options"]}
              class={[
                "group/part flex cursor-pointer items-start gap-2 rounded-lg px-2 py-1.5 text-sm transition hover:bg-base-100",
                a && o["id"] in a["answer"] && a["correct"] && "bg-success/10",
                a && o["id"] in a["answer"] && a["correct"] == false && "bg-error/10"
              ]}
            >
              <input
                type={if q["type"] == "single", do: "radio", else: "checkbox"}
                name={if q["type"] == "single", do: "answer", else: "answer[]"}
                value={o["id"]}
                checked={a != nil and o["id"] in a["answer"]}
                class="mt-1"
              />
              <span class="min-w-0 flex-1">
                {o["text"]}
                <span
                  :if={a}
                  class={[
                    "mt-0.5 block text-xs",
                    o["correct"] && "text-success font-medium",
                    !o["correct"] && "text-base-content/70"
                  ]}
                >
                  <.icon
                    name={if o["correct"], do: "hero-check-circle-mini", else: "hero-x-circle-mini"}
                    class="mr-0.5 inline size-3.5"
                  />
                  {o["explanation"]}
                </span>
              </span>
              <.part_button w={@w} part={"option:#{q["id"]}/#{o["id"]}"} ctx={@ctx} />
            </label>
            <div class="flex items-center gap-3 pt-1">
              <button
                type="submit"
                class="rounded-lg bg-primary px-3 py-1 text-sm font-medium text-primary-content hover:opacity-90"
              >
                {if a, do: "Answer again", else: "Check answer"}
              </button>
              <span
                :if={a}
                class={[
                  "text-sm font-semibold",
                  a["correct"] && "text-success",
                  !a["correct"] && "text-error"
                ]}
              >
                {if a["correct"], do: "Correct", else: "Not quite"}
              </span>
            </div>
          </form>

          <form
            :if={q["type"] == "text"}
            id={"answer-#{@w.id}-#{q["id"]}"}
            phx-submit="widget:answer"
            phx-hook="Draft"
            class="mt-2 space-y-2"
          >
            <input type="hidden" name="widget" value={@w.id} />
            <input type="hidden" name="question" value={q["id"]} />
            <textarea
              name="answer"
              rows="2"
              class="w-full rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm"
              placeholder="Answer in your own words"
            >{a && a["answer"]}</textarea>
            <button
              type="submit"
              class="rounded-lg bg-primary px-3 py-1 text-sm font-medium text-primary-content hover:opacity-90"
            >
              {if a, do: "Answer again", else: "Submit"}
            </button>
            <div :if={a} class="rounded-lg bg-base-100 p-2 text-sm">
              <%= cond do %>
                <% @d["mode"] == "self_study" -> %>
                  <p class="text-[0.6875rem] font-semibold uppercase text-base-content/70">
                    Model answer
                  </p>
                  <.markdown glossary={@ctx.glossary} text={q["model_answer"]} class="text-sm" />
                <% a["correct"] == nil -> %>
                  <p class="text-base-content/70">Waiting for the agent to judge your answer…</p>
                <% true -> %>
                  <p class={[
                    "font-semibold",
                    a["correct"] && "text-success",
                    !a["correct"] && "text-error"
                  ]}>
                    {if a["correct"], do: "Correct", else: "Not quite"}
                  </p>
                  <.markdown
                    :if={a["verdict"]}
                    glossary={@ctx.glossary}
                    text={a["verdict"]}
                    class="text-sm"
                  />
              <% end %>
            </div>
          </form>
        </li>
      </ol>
      <div :if={@total > 1} class="mt-3 flex gap-2">
        <button
          :if={@index > 0}
          id={"quiz-prev-#{@w.id}"}
          type="button"
          phx-click={JS.push("widget:ui") |> JS.focus(to: "#quiz-step-#{@w.id}")}
          phx-value-widget={@w.id}
          phx-value-key="q"
          phx-value-value={@index - 1}
          value={@index - 1}
          class="rounded-lg border border-base-300 px-2.5 py-1 text-xs font-medium hover:bg-base-200"
        >Previous question</button>
        <button
          :if={@index < @total - 1}
          id={"quiz-next-#{@w.id}"}
          type="button"
          phx-click={JS.push("widget:ui") |> JS.focus(to: "#quiz-step-#{@w.id}")}
          phx-value-widget={@w.id}
          phx-value-key="q"
          phx-value-value={@index + 1}
          value={@index + 1}
          class="rounded-lg bg-primary px-2.5 py-1 text-xs font-medium text-primary-content hover:opacity-90"
        >Next question</button>
      </div>
    </div>
    """
  end

  defp body(%{w: %{kind: "comparison"}} = assigns) do
    d = assigns.w.data
    human = assigns.w.human["weights"] || %{}
    ranked = Catalog.ranking(d, human)
    agent_order = Enum.map(Catalog.ranking(d, %{}), fn {o, _} -> o["id"] end)

    assigns =
      assign(assigns,
        d: d,
        human: human,
        ranked: ranked,
        max_total: ranked |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) |> max(1),
        changed?: human != %{},
        agent_order: agent_order
      )

    ~H"""
    <div>
      <form
        id={"weights-#{@w.id}"}
        phx-change="widget:weights"
        class="overflow-x-auto rounded-xl ring-1 ring-base-300"
      >
        <input type="hidden" name="widget" value={@w.id} />
        <table class="w-full text-sm">
          <thead class="bg-base-200/70 align-bottom text-left text-xs">
            <tr>
              <th class="px-3 py-2 font-semibold uppercase tracking-wide text-base-content/70">
                Option
              </th>
              <th :for={c <- @d["criteria"]} class="group/part min-w-28 px-3 py-2">
                <span class="flex items-center gap-1 font-semibold">
                  {c["label"]} <.part_button w={@w} part={"criterion:#{c["id"]}"} ctx={@ctx} />
                </span>
                <span class="mt-1 flex items-center gap-2">
                  <input
                    type="range"
                    min="0"
                    max="5"
                    step="1"
                    name={"w[#{c["id"]}]"}
                    value={Map.get(@human, c["id"], c["weight"])}
                    class="w-20 accent-[var(--color-primary)]"
                    aria-label={"Weight of #{c["label"]}"}
                  />
                  <span class={[
                    "font-mono",
                    Map.has_key?(@human, c["id"]) && "font-bold text-primary"
                  ]}>
                    ×{Map.get(@human, c["id"], c["weight"])}
                  </span>
                </span>
              </th>
              <th class="px-3 py-2 font-semibold uppercase tracking-wide text-base-content/70">
                Total
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={{{o, total}, rank} <- Enum.with_index(@ranked, 1)}
              id={"option-#{@w.id}-#{o["id"]}"}
              class={[
                "group/part border-t border-base-200 transition",
                @d["recommended"] == o["id"] && "bg-primary/10"
              ]}
            >
              <td class="px-3 py-2">
                <span class="flex items-center gap-2 font-medium">
                  <span class="grid size-5 place-items-center rounded-full bg-base-content font-mono text-[0.625rem] text-base-100">{rank}</span>
                  {o["label"]}
                  <span
                    :if={@d["recommended"] == o["id"]}
                    class="rounded-full bg-primary px-1.5 py-0.5 text-[0.625rem] font-semibold uppercase text-primary-content"
                  >Recommended</span>
                  <.part_button w={@w} part={"option:#{o["id"]}"} ctx={@ctx} />
                </span>
              </td>
              <td :for={c <- @d["criteria"]} class="px-3 py-2" title={o["notes"][c["id"]]}>
                <span class="flex gap-0.5" aria-label={"#{o["scores"][c["id"]] || 0} of 5"}>
                  <span
                    :for={i <- 1..5}
                    class={[
                      "size-2.5 rounded-full",
                      if(i <= (o["scores"][c["id"]] || 0), do: "bg-primary", else: "bg-base-300")
                    ]}
                  />
                </span>
                <span
                  :if={o["notes"][c["id"]]}
                  class="mt-0.5 block text-[0.6875rem] text-base-content/70"
                >{o[
                  "notes"
                ][c["id"]]}</span>
              </td>
              <td class="px-3 py-2">
                <span class="font-mono font-semibold">{total}</span>
                <span class="mt-1 block h-1.5 w-20 overflow-hidden rounded-full bg-base-200">
                  <span
                    class="block h-full bg-accent transition-all"
                    style={"width: #{total * 100 / @max_total}%"}
                  />
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </form>
      <p class="mt-2 flex flex-wrap items-center gap-2 text-xs text-base-content/70">
        Drag a weight to see how the ranking changes.
        <button
          :if={@changed?}
          type="button"
          phx-click="widget:action"
          phx-value-widget={@w.id}
          phx-value-action="reset_weights"
          class="rounded-lg px-2 py-0.5 font-medium text-primary hover:bg-primary/10"
        >
          Reset weights
        </button>
        <span
          :if={@changed? and Enum.map(@ranked, &elem(&1, 0)["id"]) != @agent_order}
          class="text-accent"
        >
          Your weights change the order.
        </span>
      </p>
    </div>
    """
  end

  defp body(%{w: %{kind: "sources"}} = assigns) do
    d = assigns.w.data
    claim_id = (assigns.ctx.ui[assigns.w.id] || %{})["claim"]
    claim = claim_id && Enum.find(d["claims"] || [], &(&1["id"] == claim_id))
    assigns = assign(assigns, d: d, claim: claim)

    ~H"""
    <div class="grid gap-4 md:grid-cols-2">
      <div>
        <h3 class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/70">
          Claims
        </h3>
        <ul class="space-y-1.5">
          <li
            :for={c <- @d["claims"] || []}
            id={"claim-#{@w.id}-#{c["id"]}"}
            class="group/part flex items-start gap-1"
          >
            <button
              type="button"
              phx-click="widget:ui"
              phx-value-widget={@w.id}
              phx-value-key="claim"
              phx-value-value={if @claim && @claim["id"] == c["id"], do: "", else: c["id"]}
              value={if @claim && @claim["id"] == c["id"], do: "", else: c["id"]}
              class={[
                "flex-1 rounded-lg px-3 py-2 text-left text-sm transition",
                if(@claim && @claim["id"] == c["id"],
                  do: "bg-primary text-primary-content",
                  else: "bg-base-200/60 hover:bg-base-200"
                )
              ]}
            >
              {c["text"]}
              <span
                :if={c["sources"] == []}
                class="ml-1 rounded bg-warning/30 px-1.5 py-0.5 text-[0.625rem] font-bold uppercase text-base-content"
              >Unsupported</span>
            </button>
            <.part_button w={@w} part={"claim:#{c["id"]}"} ctx={@ctx} />
          </li>
          <li :if={(@d["claims"] || []) == []} class="text-sm italic text-base-content/70">
            No claims.
          </li>
        </ul>
      </div>
      <div>
        <h3 class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/70">
          Sources
        </h3>
        <ul class="space-y-2">
          <li
            :for={s <- @d["sources"]}
            id={"source-#{@w.id}-#{s["id"]}"}
            class={[
              "group/part rounded-lg p-3 text-sm ring-1 transition",
              if(@claim && s["id"] in @claim["sources"],
                do: "bg-primary/10 ring-primary",
                else: "bg-base-100 ring-base-300"
              )
            ]}
          >
            <div class="flex items-start gap-1">
              <p class="min-w-0 flex-1 font-medium">
                <a
                  :if={s["url"]}
                  href={s["url"]}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="underline decoration-primary underline-offset-2"
                >{s["title"]}</a>
                <span :if={!s["url"]}>{s["title"]}</span>
              </p>
              <.part_button w={@w} part={"source:#{s["id"]}"} ctx={@ctx} />
            </div>
            <blockquote
              :if={s["quote"]}
              class="mt-1 border-l-2 border-primary/50 pl-2 text-xs italic text-base-content/70"
            >
              {s["quote"]}
            </blockquote>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp body(%{w: %{kind: "walkthrough"}} = assigns) do
    d = assigns.w.data
    steps = d["steps"]
    index = parse_index((assigns.ctx.ui[assigns.w.id] || %{})["step"], length(steps)) || 0
    step = Enum.at(steps, index)
    assigns = assign(assigns, d: d, steps: steps, index: index, step: step)

    ~H"""
    <div>
      <p :if={@d["title"]} class="mb-2 font-semibold">{@d["title"]}</p>
      <div class={["grid gap-3", length(@steps) > 1 && "lg:grid-cols-[12rem_minmax(0,1fr)]"]}>
        <ol :if={length(@steps) > 1} class="space-y-1 text-sm">
          <li :for={{s, i} <- Enum.with_index(@steps)}>
            <button
              type="button"
              id={"walk-step-#{@w.id}-#{s["id"]}"}
              phx-click="widget:ui"
              phx-value-widget={@w.id}
              phx-value-key="step"
              phx-value-value={i}
              value={i}
              class={[
                "w-full rounded-lg px-2 py-1.5 text-left transition",
                if(i == @index, do: "bg-primary text-primary-content", else: "hover:bg-base-200")
              ]}
            >
              <span class="font-mono text-[0.625rem] opacity-70">{i + 1}</span>
              <span class="block truncate font-mono text-xs">{Path.basename(s["path"])}</span>
            </button>
          </li>
        </ol>
        <div class="group/part min-w-0 space-y-2" id={"walk-current-#{@w.id}"}>
          <div class="flex items-center gap-2 text-xs">
            <span class="font-mono font-semibold">{@step["path"]}<span
              :if={@step["lines"]}
              class="text-base-content/70"
            >:{@step["lines"]}</span></span>
            <span
              :if={length(@steps) > 1}
              class="ml-auto font-semibold"
              id={"walk-counter-#{@w.id}"}
              tabindex="-1"
            >
              Step {@index + 1} of {length(@steps)}
            </span>
            <.part_button w={@w} part={"step:#{@step["id"]}"} ctx={@ctx} />
          </div>
          <div class="grid gap-3 xl:grid-cols-2">
            <.markdown
              text={fence(@step["code"], @step["language"])}
              class="text-sm [&_pre]:max-h-80"
            />
            <div class="rounded-xl bg-primary/10 p-3 ring-1 ring-primary/30">
              <.markdown glossary={@ctx.glossary} text={@step["narration"]} class="text-sm" />
            </div>
          </div>
          <div :if={length(@steps) > 1} class="flex gap-2">
            <button
              :if={@index > 0}
              id={"walk-prev-#{@w.id}"}
              type="button"
              phx-click={JS.push("widget:ui") |> JS.focus(to: "#walk-counter-#{@w.id}")}
              phx-value-widget={@w.id}
              phx-value-key="step"
              phx-value-value={@index - 1}
              value={@index - 1}
              class="rounded-lg border border-base-300 px-2.5 py-1 text-xs font-medium hover:bg-base-200 disabled:opacity-40"
            >Previous</button>
            <button
              :if={@index < length(@steps) - 1}
              id={"walk-next-#{@w.id}"}
              type="button"
              phx-click={JS.push("widget:ui") |> JS.focus(to: "#walk-counter-#{@w.id}")}
              phx-value-widget={@w.id}
              phx-value-key="step"
              phx-value-value={@index + 1}
              value={@index + 1}
              class="rounded-lg bg-primary px-2.5 py-1 text-xs font-medium text-primary-content hover:opacity-90 disabled:opacity-40"
            >Next</button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @severity_style %{
    "blocker" => "bg-error text-error-content",
    "major" => "bg-warning text-warning-content",
    "minor" => "bg-info text-info-content",
    "nit" => "bg-base-300 text-base-content"
  }

  defp body(%{w: %{kind: "findings"}} = assigns) do
    d = assigns.w.data
    filter = (assigns.ctx.ui[assigns.w.id] || %{})["sev"]
    marks = assigns.w.human["marks"] || %{}
    counts = Enum.frequencies_by(d["findings"], & &1["severity"])

    assigns =
      assign(assigns,
        d: d,
        filter: filter,
        marks: marks,
        counts: counts,
        shown: Enum.filter(d["findings"], &(filter in [nil, ""] or &1["severity"] == filter)),
        severity_style: @severity_style
      )

    ~H"""
    <div>
      <div class="mb-3 flex flex-wrap gap-1.5">
        <button
          :for={sev <- Catalog.severities()}
          :if={@counts[sev]}
          type="button"
          id={"sev-#{@w.id}-#{sev}"}
          phx-click="widget:ui"
          phx-value-widget={@w.id}
          phx-value-key="sev"
          phx-value-value={if @filter == sev, do: "", else: sev}
          value={if @filter == sev, do: "", else: sev}
          aria-pressed={to_string(@filter == sev)}
          class={[
            "rounded-full px-2.5 py-1 text-xs font-semibold transition",
            @severity_style[sev],
            @filter && @filter != sev && "opacity-40"
          ]}
        >
          {@counts[sev]} {sev}
        </button>
      </div>
      <ul class="space-y-3">
        <li
          :for={f <- @shown}
          id={"finding-#{@w.id}-#{f["id"]}"}
          class="group/part rounded-xl bg-base-200/50 p-3"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class={[
              "rounded-full px-2 py-0.5 text-[0.625rem] font-bold uppercase",
              @severity_style[f["severity"]]
            ]}>{f["severity"]}</span>
            <span class="font-mono text-xs">{f["path"]}<span :if={f["line"]}>:{f["line"]}</span></span>
            <span class="ml-auto" />
            <.part_button w={@w} part={"finding:#{f["id"]}"} ctx={@ctx} />
          </div>
          <.markdown glossary={@ctx.glossary} text={f["explanation"]} class="mt-2 text-sm" />
          <div
            :if={f["suggestion"]}
            class="mt-2 rounded-lg border-l-4 border-success bg-success/10 px-3 py-2 text-sm"
          >
            <p class="text-[0.625rem] font-bold uppercase tracking-wide text-success">
              Suggested change
            </p>
            <.markdown glossary={@ctx.glossary} text={f["suggestion"]} class="text-sm" />
          </div>
          <div class="mt-3 flex gap-1.5" role="group" aria-label={"Your answer to #{f["id"]}"}>
            <button
              :for={m <- Catalog.marks()}
              type="button"
              id={"mark-#{@w.id}-#{f["id"]}-#{m}"}
              phx-click="widget:action"
              phx-value-widget={@w.id}
              phx-value-action="mark"
              phx-value-finding={f["id"]}
              phx-value-mark={m}
              aria-pressed={to_string(@marks[f["id"]] == m)}
              class={[
                "rounded-lg px-2.5 py-1 text-xs font-medium capitalize transition",
                if(@marks[f["id"]] == m,
                  do: "bg-primary text-primary-content",
                  else: "border border-base-300 hover:bg-base-100"
                )
              ]}
            >
              {m}
            </button>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  defp body(%{w: %{kind: "discussion"}} = assigns) do
    items = assigns.w.data["items"] || []
    {open, rest} = Enum.split_with(items, &Catalog.open_item/1)
    assigns = assign(assigns, open: open, rest: rest, items: items)

    ~H"""
    <div id={"discussion-#{@w.id}"} class="space-y-3 text-sm">
      <p
        :if={@w.data["status"] == "not_read"}
        id={"discussion-#{@w.id}-not-read"}
        class="rounded-xl border-l-4 border-warning bg-warning/10 px-3 py-2"
      >
        <span class="font-semibold">Discussion not read.</span> {@w.data["error"]}
      </p>
      <p
        :if={@w.data["status"] == "read" and @items == []}
        id={"discussion-#{@w.id}-none"}
        class="italic text-base-content/70"
      >
        No existing discussion.
      </p>
      <.discussion_group
        :if={@open != []}
        id={"discussion-#{@w.id}-open"}
        title="Unresolved and requested changes"
        items={@open}
        w={@w}
        ctx={@ctx}
      />
      <.discussion_group
        :if={@rest != []}
        id={"discussion-#{@w.id}-rest"}
        title="Resolved and other"
        items={@rest}
        w={@w}
        ctx={@ctx}
      />
    </div>
    """
  end

  defp body(%{w: %{kind: "round"}} = assigns) do
    d = assigns.w.data

    assigns =
      assign(assigns,
        d: d,
        same?: d["head"] == d["previous_head"],
        mine: assigns.w.human["statuses"] || %{}
      )

    ~H"""
    <div id={"round-#{@w.id}"} class="space-y-3 text-sm">
      <p class="font-semibold">
        Round {@d["number"]}
        <span class="ml-1 font-mono text-xs font-normal text-base-content/70">
          {@d["previous_head"]} → {@d["head"]}
        </span>
      </p>
      <p
        :if={@same?}
        id={"round-#{@w.id}-no-commits"}
        class="rounded-xl bg-base-200/50 px-3 py-2 italic"
      >
        No new commits since the previous round; finding statuses are unchanged.
      </p>
      <ul :if={!@same?} class="space-y-1">
        <li
          :for={c <- @d["commits"] || []}
          id={"commit-#{@w.id}-#{c["id"]}"}
          class="group/part flex items-center gap-2"
        >
          <span class="font-mono text-xs">{c["sha"]}</span>
          <span>{c["subject"]}</span>
          <span class="ml-auto" />
          <.part_button w={@w} part={"commit:#{c["id"]}"} ctx={@ctx} />
        </li>
      </ul>
      <ul :if={!@same?} class="space-y-3">
        <li
          :for={s <- @d["statuses"] || []}
          id={"status-#{@w.id}-#{s["id"]}"}
          class="group/part rounded-xl bg-base-200/50 p-3"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-mono text-xs">finding {s["finding"]}</span>
            <span class={[
              "rounded-full px-2 py-0.5 text-[0.625rem] font-bold uppercase",
              case s["status"] do
                "resolved" -> "bg-success text-success-content"
                "open" -> "bg-warning text-warning-content"
                _ -> "bg-error text-error-content"
              end
            ]}>
              {if s["status"] == "location_gone", do: "location gone", else: s["status"]}
            </span>
            <span class="font-mono text-xs text-base-content/70">
              {if s["status"] == "location_gone", do: "was " <> s["old_location"], else: s["location"]}
            </span>
            <span class="ml-auto" />
            <.part_button w={@w} part={"status:#{s["id"]}"} ctx={@ctx} />
          </div>
          <.markdown glossary={@ctx.glossary} text={s["reason"]} class="mt-2 text-sm" />
          <div
            class="mt-3 flex items-center gap-1.5"
            role="group"
            aria-label={"Your status for #{s["finding"]}"}
          >
            <span class="mr-1 text-xs text-base-content/70">
              {if @mine[s["id"]], do: "Your status:", else: "Not confirmed:"}
            </span>
            <button
              :for={v <- ~w(resolved open)}
              type="button"
              id={"status-#{@w.id}-#{s["id"]}-#{v}"}
              phx-click="widget:action"
              phx-value-widget={@w.id}
              phx-value-action="status"
              phx-value-id={s["id"]}
              phx-value-value={v}
              value={v}
              aria-pressed={to_string(@mine[s["id"]] == v)}
              class={[
                "rounded-lg px-2.5 py-1 text-xs font-medium capitalize transition",
                if(@mine[s["id"]] == v,
                  do: "bg-primary text-primary-content",
                  else: "border border-base-300 hover:bg-base-100"
                )
              ]}
            >
              {v}
            </button>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  defp body(%{w: %{kind: "draft_comments"}} = assigns) do
    d = assigns.w.data
    h = assigns.w.human
    decisions = h["decisions"] || %{}
    approved = Catalog.approved_drafts(d, h)

    assigns =
      assign(assigns,
        d: d,
        decisions: decisions,
        verdict: h["verdict"],
        stale?: Catalog.stale?(d),
        can_post?: approved != [] and h["verdict"] != nil,
        approved_count: length(approved)
      )

    ~H"""
    <div id={"drafts-#{@w.id}"} class="space-y-3 text-sm">
      <p
        :if={@stale?}
        id={"drafts-#{@w.id}-stale"}
        class="rounded-xl border-l-4 border-warning bg-warning/10 px-3 py-2"
      >
        The pull request head moved from <span class="font-mono">{@d["head"]}</span>
        to <span class="font-mono">{@d["current_head"]}</span>: these comments are possibly out of date.
      </p>
      <ul class="space-y-4">
        <li
          :for={c <- @d["comments"]}
          id={"draft-#{@w.id}-#{c["id"]}"}
          class="group/part rounded-xl bg-base-200/50 p-3"
        >
          <% anchored? = Catalog.anchored?(c) %>
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-mono text-xs">{c["path"]}:{c["line"]}</span>
            <span
              :if={c["posted_url"]}
              class="rounded-full bg-success px-2 py-0.5 text-[0.625rem] font-bold uppercase text-success-content"
            >posted</span>
            <span
              :if={!c["posted_url"] and @stale?}
              class="rounded-full bg-warning px-2 py-0.5 text-[0.625rem] font-bold uppercase text-warning-content"
            >possibly out of date</span>
            <span
              :if={!anchored?}
              id={"draft-#{@w.id}-#{c["id"]}-flag"}
              class="rounded-full bg-error px-2 py-0.5 text-[0.625rem] font-bold uppercase text-error-content"
            >line not in the diff</span>
            <span class="ml-auto" />
            <.part_button w={@w} part={"anchor:#{c["id"]}"} ctx={@ctx} />
          </div>
          <pre class="mt-2 overflow-x-auto rounded-lg bg-base-100 py-1 font-mono text-[0.6875rem] leading-relaxed"><span
              :for={l <- Catalog.hunk_lines(c["hunk"])}
              class={[
                "block whitespace-pre px-2",
                l.kind == :add && "bg-success/10",
                l.kind == :del && "bg-error/10",
                marked?(l, c) && "border-l-4 border-primary bg-primary/20 font-bold"
              ]}
              data-marked={to_string(marked?(l, c))}
            >{l.text}</span></pre>
          <div class="group/part mt-2 flex items-start gap-2 rounded-lg border border-base-300 bg-base-100 p-2">
            <.markdown glossary={@ctx.glossary} text={c["body"]} class="flex-1 text-sm" />
            <.part_button w={@w} part={"comment:#{c["id"]}"} ctx={@ctx} />
          </div>
          <div
            :if={!c["posted_url"]}
            class="mt-3 flex items-center gap-1.5"
            role="group"
            aria-label={"Decide on draft #{c["id"]}"}
          >
            <button
              :for={
                {action, label, state} <- [
                  {"approve", "Approve", "approved"},
                  {"drop", "Drop", "dropped"}
                ]
              }
              type="button"
              id={"draft-#{@w.id}-#{c["id"]}-#{action}"}
              phx-click="widget:action"
              phx-value-widget={@w.id}
              phx-value-action={action}
              phx-value-comment={c["id"]}
              disabled={action == "approve" and !anchored?}
              aria-pressed={to_string(@decisions[c["id"]] == state)}
              class={[
                "rounded-lg px-2.5 py-1 text-xs font-medium transition disabled:cursor-not-allowed disabled:opacity-40",
                if(@decisions[c["id"]] == state,
                  do: "bg-primary text-primary-content",
                  else: "border border-base-300 hover:bg-base-100"
                )
              ]}
            >
              {label}
            </button>
          </div>
          <a
            :if={c["posted_url"]}
            href={c["posted_url"]}
            target="_blank"
            rel="noopener noreferrer"
            id={"draft-#{@w.id}-#{c["id"]}-link"}
            class="mt-2 inline-block text-xs text-primary underline"
          >View on the code host</a>
        </li>
      </ul>
      <div class="group/part flex flex-wrap items-center gap-2 border-t border-base-200 pt-3">
        <span class="text-xs font-semibold uppercase tracking-wide text-base-content/70">Verdict</span>
        <button
          :for={v <- Catalog.verdicts()}
          type="button"
          id={"verdict-#{@w.id}-#{v}"}
          phx-click="widget:action"
          phx-value-widget={@w.id}
          phx-value-action="verdict"
          phx-value-value={v}
          value={v}
          aria-pressed={to_string(@verdict == v)}
          class={[
            "rounded-lg px-2.5 py-1 text-xs font-medium transition",
            if(@verdict == v,
              do: "bg-primary text-primary-content",
              else: "border border-base-300 hover:bg-base-100"
            )
          ]}
        >
          {String.replace(v, "_", " ")}
        </button>
        <.part_button w={@w} part="verdict" ctx={@ctx} />
        <span class="ml-auto" />
        <button
          type="button"
          id={"drafts-#{@w.id}-post"}
          phx-click="widget:action"
          phx-value-widget={@w.id}
          phx-value-action="post"
          disabled={!@can_post?}
          class="rounded-lg bg-primary px-3 py-1.5 text-xs font-semibold text-primary-content transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
        >
          Post {@approved_count} approved
        </button>
      </div>
    </div>
    """
  end

  defp marked?(l, c) do
    key = if c["side"] == "LEFT", do: :old, else: :new
    Map.get(l, key) == String.to_integer(c["line"])
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :w, :map, required: true
  attr :ctx, :map, required: true

  defp discussion_group(assigns) do
    ~H"""
    <div id={@id}>
      <h3 class="mb-1.5 text-xs font-semibold uppercase tracking-wide text-base-content/70">
        {@title}
      </h3>
      <ul class="space-y-2">
        <li
          :for={i <- @items}
          id={"item-#{@w.id}-#{i["id"]}"}
          class="group/part rounded-xl bg-base-200/50 p-3"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span class="font-medium">{i["author"]}</span>
            <span class="text-xs text-base-content/70">{String.replace(i["type"], "_", " ")}</span>
            <span
              :if={i["state"]}
              class="rounded-full bg-base-300 px-2 py-0.5 text-[0.625rem] font-bold uppercase"
            >
              {String.replace(i["state"], "_", " ")}
            </span>
            <span :if={i["path"]} class="font-mono text-xs">{i["path"]}<span :if={i["line"]}>:{i[
              "line"
            ]}</span></span>
            <span :if={i["type"] == "thread"} class="text-xs text-base-content/70">
              {if i["resolved"] == true, do: "resolved", else: "unresolved"}
            </span>
            <span class="ml-auto" />
            <.part_button w={@w} part={"item:#{i["id"]}"} ctx={@ctx} />
          </div>
          <.markdown :if={i["body"]} glossary={@ctx.glossary} text={i["body"]} class="mt-1 text-sm" />
        </li>
      </ul>
    </div>
    """
  end

  ## Lifecycle

  attr :type, :atom, required: true
  attr :step, :string, required: true
  attr :previous, :string, default: nil

  attr :transitions, :list,
    required: true,
    doc: "`%{t: transition, unmet: [reasons]}` out of the current step"

  attr :simulate_agent?, :boolean, default: false
  attr :event, :string, default: "move"

  attr :confirming, :string,
    default: nil,
    doc:
      "the transition the human chose and must confirm; its card shows from, to, and what happens next"

  @doc """
  The lifecycle of a task type as a graph, and the moves out of the current step.

  Choosing a move sends `move_ask`; the card then shows the from-step, the
  to-step, and what happens next, and only its confirm button sends `@event`.
  `move_cancel` closes the confirmation.
  """
  def lifecycle(assigns) do
    assigns = assign(assigns, :next, for(%{t: t} <- assigns.transitions, do: t.to))

    ~H"""
    <div id="lifecycle" tabindex="-1" class="space-y-4">
      <.lifecycle_graph type={@type} step={@step} previous={@previous} next={@next} />

      <div class="grid gap-2 md:grid-cols-2">
        <p :if={@transitions == []} class="text-sm italic text-base-content/70">
          This step ends the lifecycle.
        </p>
        <div
          :for={%{t: t, unmet: unmet} <- @transitions}
          id={"transition-#{dashed(t.name)}"}
          tabindex="-1"
          class="rounded-xl border border-base-300 p-3"
        >
          <div class="flex items-center gap-2">
            <.icon
              name={if t.mover == :human, do: "hero-user", else: "hero-cpu-chip"}
              class="size-4 text-base-content/70"
            />
            <p class="font-medium">{t.name}</p>
            <span class="ml-auto text-xs text-base-content/70">→ {TaskType.step_label(@type, t.to)}</span>
          </div>
          <p class="mt-1 text-xs text-base-content/70">
            <%= if t.mover == :human do %>
              Your decision.
            <% else %>
              An agent moves it: run <code class="rounded bg-base-200 px-1">{t.command}</code>.
            <% end %>
          </p>
          <p :for={reason <- unmet} class="mt-1 flex items-center gap-1 text-xs text-warning-content">
            <span class="rounded bg-warning/30 px-1.5 py-0.5 text-base-content">{reason}</span>
          </p>
          <div
            :if={@confirming == t.name}
            id={"move-confirmation-#{dashed(t.name)}"}
            role="group"
            aria-label={"Confirm #{t.name}"}
            class="mt-2 rounded-lg border-2 border-base-content/70 p-3 text-sm"
          >
            <p>
              From <strong>{TaskType.step_label(@type, @step)}</strong>
              to <strong>{TaskType.step_label(@type, t.to)}</strong>.
            </p>
            <p class="mt-1">Next: {TaskType.step_description(@type, t.to)}.</p>
            <div class="mt-2 flex flex-wrap gap-2">
              <button
                id={"move-confirm-#{dashed(t.name)}"}
                type="button"
                phx-click={JS.push(@event) |> JS.focus(to: "#lifecycle")}
                phx-value-transition={t.name}
                phx-mounted={JS.focus()}
                class="rounded-lg bg-primary px-3 py-1.5 text-sm font-medium text-primary-content hover:opacity-90"
              >
                Move to {TaskType.step_label(@type, t.to)}
              </button>
              <button
                id={"move-cancel-#{dashed(t.name)}"}
                type="button"
                phx-click={JS.push("move_cancel") |> JS.focus(to: "#transition-#{dashed(t.name)}")}
                class="rounded-lg border border-base-300 px-3 py-1.5 text-sm font-medium hover:bg-base-200"
              >
                Keep it in {TaskType.step_label(@type, @step)}
              </button>
            </div>
          </div>
          <button
            :if={(t.mover == :human or @simulate_agent?) and @confirming != t.name}
            id={"move-ask-#{dashed(t.name)}"}
            type="button"
            phx-click="move_ask"
            phx-value-transition={t.name}
            disabled={unmet != []}
            class={[
              "mt-2 rounded-lg px-3 py-1.5 text-sm font-medium transition active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-40",
              if(t.mover == :human,
                do: "bg-primary text-primary-content hover:opacity-90",
                else: "border border-base-300 hover:bg-base-200"
              )
            ]}
          >
            {if t.mover == :human, do: t.name, else: "Act as the agent: #{t.name}"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :type, :atom, required: true
  attr :step, :string, default: nil, doc: "the current step; `nil` highlights none"
  attr :previous, :string, default: nil
  attr :next, :list, default: [], doc: "keys of the steps the current step can move to"
  attr :prefix, :string, default: "", doc: "prefixed to every DOM id in the graph"

  @doc """
  The graph of a task type's lifecycle: steps as nodes (`<prefix>step-<key>`
  with `data-state`), transitions as named arrows, transitions back dashed.
  Without a step nothing is highlighted. The prefix goes on every id, including
  the arrow markers, so several graphs can share a page.
  """
  def lifecycle_graph(assigns) do
    steps = TaskType.steps(assigns.type)
    order = steps |> Enum.map(&elem(&1, 0)) |> Enum.with_index() |> Map.new()
    next = MapSet.new(assigns.next)

    nodes =
      for {key, label, hint} <- steps,
          do: {key, label, hint, step_state(key, assigns.step, assigns.previous, next, order)}

    assigns =
      assign(assigns,
        layout: GraphLayout.lifecycle(steps, TaskType.transitions(assigns.type)),
        nodes: nodes
      )

    ~H"""
    <div class="overflow-x-auto pb-1">
      <div class="relative" style={"width: #{@layout.width}px; height: #{@layout.height}px"}>
        <svg
          class="absolute inset-0"
          width={@layout.width}
          height={@layout.height}
          aria-hidden="true"
        >
          <defs>
            <marker
              id={"#{@prefix}lc-arrow"}
              viewBox="0 0 10 10"
              refX="9"
              refY="5"
              markerWidth="7"
              markerHeight="7"
              orient="auto"
            >
              <path d="M0,0 L10,5 L0,10 z" class="fill-secondary" />
            </marker>
            <marker
              id={"#{@prefix}lc-arrow-on"}
              viewBox="0 0 10 10"
              refX="9"
              refY="5"
              markerWidth="7"
              markerHeight="7"
              orient="auto"
            >
              <path d="M0,0 L10,5 L0,10 z" class="fill-primary" />
            </marker>
          </defs>
          <g :for={arc <- @layout.arcs}>
            <path
              d={arc.d}
              fill="none"
              marker-end={
                if arc.t.from == @step,
                  do: "url(##{@prefix}lc-arrow-on)",
                  else: "url(##{@prefix}lc-arrow)"
              }
              stroke-dasharray={if arc.dir == :back, do: "5 4"}
              class={[
                cond do
                  arc.t.from == @step -> "stroke-primary"
                  is_nil(@step) -> "stroke-secondary opacity-70"
                  true -> "stroke-secondary opacity-40"
                end
              ]}
              stroke-width={if arc.t.from == @step, do: 2.5, else: 1.5}
            />
            <text
              x={arc.lx}
              y={arc.ly}
              text-anchor="middle"
              class={[
                "text-[0.625rem]",
                cond do
                  arc.t.from == @step -> "fill-primary font-semibold"
                  is_nil(@step) -> "fill-base-content opacity-80"
                  true -> "fill-base-content opacity-50"
                end
              ]}
            >
              {arc.t.name}
            </text>
          </g>
        </svg>
        <div
          :for={{key, label, hint, state} <- @nodes}
          id={"#{@prefix}step-#{key}"}
          data-state={state}
          title={hint}
          class={[
            "absolute flex flex-col items-center justify-center rounded-xl px-2 text-center text-sm font-medium transition",
            case state do
              "current" -> "bg-primary text-primary-content shadow-lg ring-4 ring-primary/25"
              "previous" -> "border-2 border-dashed border-accent bg-base-100"
              "next" -> "border-2 border-primary bg-primary/5"
              "passed" -> "bg-base-200 text-base-content/70"
              "plain" -> "border border-base-300 bg-base-100"
              _ -> "border border-base-300 bg-base-100 text-base-content/70"
            end
          ]}
          style={node_style(@layout.steps[key])}
        >
          <span>{label}</span>
          <span class="text-[0.625rem] font-normal uppercase tracking-wide">
            {case state do
              "current" -> "you are here"
              "previous" -> "came from"
              "next" -> "next"
              _ -> ""
            end}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp dashed(name), do: String.replace(name, " ", "-")

  # Part ids are written by agents; encoding keeps the DOM id a valid selector.
  defp comment_button_id(widget_id, nil), do: "comment-on-#{widget_id}"

  defp comment_button_id(widget_id, part),
    do: "comment-on-#{widget_id}-" <> Base.url_encode64(part, padding: false)

  # Where the explanation of a selected part sits: right under its node or
  # group, or at its edge's label, so it is read together with the part.
  defp detail_position("node:" <> id, layout) do
    case layout.nodes[id] do
      %{x: x, y: y, h: h} -> {x, y + h + 8}
      _ -> nil
    end
  end

  defp detail_position("group:" <> id, layout) do
    case Enum.find(layout.groups, &(&1.id == id)) do
      %{x: x, y: y} -> {x + 8, y + 28}
      _ -> nil
    end
  end

  defp detail_position("edge:" <> id, layout) do
    case Enum.find(layout.edges, &(&1.id == id)) do
      %{lx: lx, ly: ly} -> {lx - 128, ly + 8}
      _ -> nil
    end
  end

  defp detail_position(_part, _layout), do: nil

  defp step_state(key, step, previous, next, order) do
    cond do
      is_nil(step) -> "plain"
      key == step -> "current"
      key == previous -> "previous"
      MapSet.member?(next, key) -> "next"
      order[key] < order[step] -> "passed"
      true -> "other"
    end
  end

  ## Helpers

  defp node_style(%{x: x, y: y, w: w, h: h}),
    do: "left: #{x}px; top: #{y}px; width: #{w}px; height: #{h}px"

  defp parse_index(nil, _size), do: nil
  defp parse_index("", _size), do: nil

  defp parse_index(value, size) do
    case Integer.parse(to_string(value)) do
      {i, ""} when i >= 0 and i < size -> i
      _ -> nil
    end
  end

  defp fence(code, language) do
    longest =
      ~r/`+/
      |> Regex.scan(code)
      |> Enum.map(fn [m] -> String.length(m) end)
      |> Enum.max(fn -> 0 end)

    ticks = String.duplicate("`", max(3, longest + 1))
    "#{ticks}#{language}\n#{code}\n#{ticks}"
  end

  @doc """
  The `{pattern, meaning}` pairs of a goal's glossary widgets, longest term
  first. A pattern matches the term as a whole word, and its inflected forms in
  the board `language` (`"sv"` or `"en"`, see `Jarvis.Language`).
  """
  def glossary(goal_widgets, language) do
    for(%{kind: "glossary_term", data: d} <- goal_widgets, do: {d["term"], d["meaning"]})
    |> Enum.sort_by(fn {term, _} -> -String.length(term) end)
    |> Enum.map(fn {term, meaning} -> {term_pattern(term, language), meaning} end)
  end

  # Swedish endings on the last word: definite (-en, -et, -n, -t), plural
  # (-ar, -er, -or, -r, -n), definite plural (-arna, -erna, -orna, -rna, -na),
  # each optionally genitive (-s). A term ending in -a or -e drops it before
  # -ar, -er, -or, or -na (tavla, tavlor; pojke, pojkar; flyttare, flyttarna).
  # Stem changes (nyckel, nycklar) are not matched.
  @sv_endings "(?:arna|erna|orna|rna|na|ar|er|or|en|et|r|n|t)?s?"
  @en_endings "(?:'s|’s|es|s)?"

  defp term_pattern(term, language) do
    term = String.trim(term)
    escaped = Regex.escape(term)

    forms =
      case language do
        "sv" ->
          dropped =
            if String.match?(term, ~r/\p{L}{2}[ae]$/iu),
              do: [Regex.escape(String.slice(term, 0..-2//1)) <> "(?:(?:ar|er|or)(?:na)?|na)s?"],
              else: []

          [escaped <> @sv_endings | dropped]

        _ ->
          [escaped <> @en_endings]
      end

    Regex.compile!(
      "(?<![\\p{L}\\p{N}])(?:" <> Enum.join(forms, "|") <> ")(?![\\p{L}\\p{N}])",
      "iu"
    )
  end

  @doc "Time-stamps comments and builds the context every widget needs."
  def context(opts) do
    Map.merge(
      %{
        ui: %{},
        comments: [],
        composer: nil,
        listening: false,
        sandbox: false,
        changed: MapSet.new(),
        glossary: [],
        now: DateTime.utc_now()
      },
      Map.new(opts)
    )
  end
end
