defmodule JarvisWeb.DesignSystemLive do
  @moduledoc """
  The design system as a playground: every widget kind with example data, the
  lifecycle graph, the theme, and the comment loop. Everything here lives in
  memory, so the human can click, answer, comment, and move tasks without
  touching a board; a simulated agent answers comments and judges answers.
  """
  use JarvisWeb, :live_view

  alias Jarvis.{Planning, Theme}
  alias Jarvis.Planning.{Catalog, Comment, Task, TaskType, Widget}

  import JarvisWeb.WidgetComponents

  @guides [
    {"requirement",
     "A requirement as trigger → system → response. Its EARS pattern sets its color, so you see the structure at a glance.",
     "Confirm one. Then press Question and send a comment: the simulated agent revises the card, and your confirmation is cleared because the text changed."},
    {"examples",
     "Concrete examples of a rule that you explore instead of read (explorable explanation).",
     "Pick Plan = pro and Seats = 1 to hit a combination no row covers."},
    {"callout", "A note that must not be missed: info, warning, or risk.",
     "Hover the card and comment on it."},
    {"prose", "Markdown, for what no other widget expresses better.",
     "Agents are asked to prefer other widgets."},
    {"glossary_term", "A domain term introduced before it is used (pre-training).",
     "Terms in a goal's Glossary are written as these."},
    {"decision", "A decision with its reason and the alternatives rejected.",
     "Look at what was rejected, not only what was chosen."},
    {"diagram", "Mermaid diagrams: flowcharts, sequences, states, classes, ER, C4.",
     "Click a node or an edge to comment on exactly that part. Break the source in the agent view to see the render error path."},
    {"architecture",
     "Typed nodes in groups with labelled edges and a guided tour, laid out by Jarvis.",
     "Start the tour and step through at your own pace (segmenting). Click a node, drag to pan, scroll to zoom."},
    {"comparison",
     "Options scored against weighted criteria; the human re-weighs and the ranking follows.",
     "Drag a weight slider until the recommended option loses its first place."},
    {"sources", "Sources with quotes, and the claims each one supports.",
     "Select a claim to light up its sources; find the unsupported one."},
    {"walkthrough",
     "Code explained one step at a time, narration beside the code (spatial contiguity).",
     "Step through, or jump to a file."},
    {"findings", "Review findings with severity; you answer each one.",
     "Filter by severity and mark findings Agree, Disagree, or Fixed."},
    {"discussion",
     "What others already said on a pull request; open threads and requested changes come first.",
     "Comment on any item."},
    {"round", "A re-review round: new commits and a proposed status for each earlier finding.",
     "Confirm or change each status."},
    {"draft_comments",
     "Review comments previewed on their diff hunk, posted only after you approve and choose a verdict.",
     "Approve or drop each draft, choose a verdict, then post."},
    {"quiz",
     "Questions that check understanding (retrieval practice). Three quizzes below: self-study, feedback, and gate.",
     "Answer the free-text question in the feedback quiz: the simulated agent judges it. Answer the gate quiz to unlock “passed” in the Learn lifecycle."}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Design system")
     |> assign(:sandbox?, true)
     |> assign(:ui, %{})
     |> assign(:composer, nil)
     |> assign(:confirming, nil)
     |> assign(:comments, [])
     |> assign(:type, :feature)
     |> assign(:step, "requirements")
     |> assign(:previous, nil)
     |> assign(:widgets, sandbox_widgets())
     |> assign(:guides, @guides)}
  end

  defp sandbox_widgets do
    example = &Catalog.example/1

    requirements = [
      {"requirement", example.("requirement") |> Map.merge(%{"id" => "R1"})},
      {"requirement",
       %{
         "id" => "R2",
         "pattern" => "unwanted",
         "trigger" => "an agent submits widget data that does not match its kind",
         "system" => "board",
         "response" => "reject the change and name every invalid field"
       }},
      {"requirement",
       %{
         "id" => "R3",
         "pattern" => "ubiquitous",
         "system" => "board",
         "response" => "show every widget in the colors of the theme"
       }}
    ]

    quizzes = [
      {"quiz", example.("quiz")},
      {"quiz", example.("quiz") |> Map.put("mode", "feedback")},
      {"quiz",
       %{
         "mode" => "gate",
         "gates" => "passed",
         "questions" => [
           %{
             "id" => "g1",
             "prompt" => "Which colors does the whole theme derive from?",
             "type" => "multiple",
             "options" => [
               %{
                 "id" => "a",
                 "text" => "Primary",
                 "correct" => true,
                 "explanation" => "One of the three brand colors."
               },
               %{
                 "id" => "b",
                 "text" => "Secondary",
                 "correct" => true,
                 "explanation" => "One of the three brand colors."
               },
               %{
                 "id" => "c",
                 "text" => "Accent",
                 "correct" => true,
                 "explanation" => "One of the three brand colors."
               },
               %{
                 "id" => "d",
                 "text" => "Success",
                 "explanation" => "Status colors are fixed, not brand colors."
               }
             ]
           }
         ]
       }}
    ]

    kinds =
      for kind <-
            ~w(examples callout prose glossary_term decision diagram architecture comparison sources walkthrough findings discussion round draft_comments),
          do: {kind, example.(kind)}

    (requirements ++ kinds ++ quizzes)
    |> Enum.with_index(1)
    |> Enum.map(fn {{kind, data}, i} ->
      {:ok, data} = Catalog.validate(kind, data)
      %Widget{id: -i, kind: kind, section: "sandbox", data: data, human: %{}}
    end)
  end

  ## Events

  @impl true
  def handle_event("widget:" <> _ = event, params, socket),
    do: JarvisWeb.WidgetEvents.handle(event, params, socket)

  def handle_event("type", %{"type" => type}, socket) do
    type = TaskType.parse(type)

    {:noreply,
     assign(socket, type: type, step: TaskType.first_step(type), previous: nil, confirming: nil)}
  end

  def handle_event("restart", _params, socket),
    do: {:noreply, assign(socket, step: TaskType.first_step(socket.assigns.type), previous: nil)}

  def handle_event("move_ask", %{"transition" => name}, socket),
    do: {:noreply, assign(socket, :confirming, name)}

  def handle_event("move_cancel", _params, socket),
    do: {:noreply, assign(socket, :confirming, nil)}

  def handle_event("move", %{"transition" => name}, socket) do
    socket = assign(socket, :confirming, nil)

    %{type: type, step: step, widgets: widgets} = socket.assigns
    transition = TaskType.find_transition(type, step, name)

    if transition &&
         Planning.unmet_conditions(%Task{type: type, step: step}, transition, widgets) == [] do
      {:noreply, assign(socket, step: transition.to, previous: step)}
    else
      {:noreply, socket}
    end
  end

  ## The simulated agent

  @impl true
  def handle_info({:sandbox_reply, comment}, socket) do
    Process.send_after(self(), {:sandbox_agent, comment}, 800)
    {:noreply, socket}
  end

  def handle_info({:sandbox_agent, comment}, socket) do
    now = DateTime.utc_now()
    widget = Enum.find(socket.assigns.widgets, &(&1.id == comment.widget_id))

    comments =
      Enum.map(socket.assigns.comments, fn c ->
        if c.id == comment.id, do: %{c | delivered_at: now}, else: c
      end)

    socket = assign(socket, :comments, comments)

    {socket, note} =
      if widget && widget.kind == "requirement" && comment.part == nil do
        revise(socket, widget)
      else
        {socket, "I would answer here, or change the widget with `jarvis_widgets`."}
      end

    reply =
      JarvisWeb.WidgetEvents.sandbox_comment(
        widget,
        comment.part,
        :agent,
        "_(simulated agent)_ " <> note
      )

    {:noreply, JarvisWeb.WidgetEvents.add_sandbox_comment(socket, reply)}
  end

  def handle_info({:sandbox_judge, widget_id, comment}, socket) do
    Process.send_after(self(), {:sandbox_judged, widget_id, comment}, 900)
    {:noreply, socket}
  end

  def handle_info({:sandbox_judged, widget_id, comment}, socket) do
    with "question:" <> qid <- comment.part,
         %Widget{kind: "quiz"} = widget <-
           Enum.find(socket.assigns.widgets, &(&1.id == widget_id)),
         {:ok, human} <-
           Catalog.judge(
             widget,
             qid,
             true,
             "_(simulated agent)_ Close enough to the model answer."
           ) do
      {:noreply,
       assign(
         socket,
         :widgets,
         Enum.map(
           socket.assigns.widgets,
           &if(&1.id == widget_id, do: %{&1 | human: human}, else: &1)
         )
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  defp revise(socket, widget) do
    revised =
      widget.data
      |> Map.update!(
        "response",
        &if(String.ends_with?(&1, " within 2 seconds"), do: &1, else: &1 <> " within 2 seconds")
      )

    human = Catalog.reconcile("requirement", widget.data, revised, widget.human)
    widget = %{widget | data: revised, human: human}

    note = %Comment{
      id: -System.unique_integer([:positive]),
      author: :system,
      body: "Widget updated",
      widget_id: widget.id,
      anchor_label: Planning.anchor_label(widget, nil),
      inserted_at: DateTime.utc_now()
    }

    socket =
      socket
      |> assign(
        :widgets,
        Enum.map(socket.assigns.widgets, &if(&1.id == widget.id, do: widget, else: &1))
      )
      |> JarvisWeb.WidgetEvents.add_sandbox_comment(note)

    {socket,
     "I made the response measurable. Your confirmation is cleared because the text changed; confirm it again if you agree."}
  end

  ## View

  @impl true
  def render(assigns) do
    widgets = assigns.widgets

    assigns =
      assign(assigns,
        ctx:
          context(
            ui: assigns.ui,
            comments: assigns.comments,
            composer: assigns.composer,
            listening: :next_turn,
            sandbox: true,
            now: DateTime.utc_now()
          ),
        transitions:
          for(
            t <- TaskType.transitions_from(assigns.type, assigns.step),
            do: %{
              t: t,
              unmet:
                Planning.unmet_conditions(
                  %Task{type: assigns.type, step: assigns.step},
                  t,
                  widgets
                )
            }
          ),
        palette: Theme.palette(Theme.current(), :light),
        by_kind: Enum.group_by(widgets, & &1.kind)
      )

    ~H"""
    <Layouts.app
      form={:reference}
      flash={@flash}
      theme_css={@theme_css}
      crumbs={[{"Design system", ~p"/design-system"}]}
    >
      <header class="max-w-3xl">
        <h1 class="text-2xl font-semibold tracking-tight">Design system</h1>
        <p class="mt-2 max-w-[70ch]">
          Every widget kind agents can show you, with the same fields for each. Nothing here touches a board.
          A simulated agent answers your comments.
          <.link navigate={~p"/guide"} class="underline">The Guide explains how comments reach agents.</.link>
        </p>
        <nav id="design-nav" class="mt-4 flex flex-wrap gap-1.5 text-sm" aria-label="On this page">
          <a href="#theme" class="rounded-full bg-base-200 px-3 py-1 hover:bg-primary/10">Theme</a>
          <a href="#lifecycle-demo" class="rounded-full bg-base-200 px-3 py-1 hover:bg-primary/10">Lifecycle</a>
          <a
            :for={{kind, _, _} <- @guides}
            href={"#kind-#{kind}"}
            class="rounded-full bg-base-200 px-3 py-1 hover:bg-primary/10"
          >
            {Catalog.label(kind)}
          </a>
        </nav>
      </header>

      <section id="theme" class="mt-10">
        <div class="flex items-end justify-between gap-3">
          <h2 class="text-lg font-semibold">Theme</h2>
          <.link navigate={~p"/settings"} class="text-sm text-primary hover:underline">Change brand colors →</.link>
        </div>
        <p class="mt-1 text-sm text-base-content/70">
          Three brand colors drive everything. Each one is adjusted so its text reads at 4.5:1 or better.
        </p>
        <div id="palette" class="mt-3 grid gap-3 sm:grid-cols-3">
          <div :for={name <- Theme.names()} class="overflow-hidden rounded-2xl border border-base-300">
            <div
              class="px-4 py-6 text-lg font-semibold capitalize"
              style={"background: #{@palette |> List.keyfind(name, 0) |> elem(1)}; color: #{@palette |> List.keyfind(name <> "-content", 0) |> elem(1)}"}
            >
              {name}
            </div>
            <p class="bg-base-100 px-4 py-2 font-mono text-xs text-base-content/70">
              {Theme.current()[name]}
            </p>
          </div>
        </div>
      </section>

      <section id="lifecycle-demo" class="mt-10">
        <h2 class="text-lg font-semibold">Lifecycles</h2>
        <p class="mt-1 max-w-3xl text-sm text-base-content/70">
          Each task type has its own lifecycle. The graph shows where a task is, where it came from, and where it can go.
          Here you play both roles: your own decisions are buttons, and agent moves have an “Act as the agent” button.
          Some moves wait for a condition. Confirm every requirement card below to unlock <em>approve requirements</em>.
          Pass the gate quiz to unlock the Learn move <em>passed</em>.
        </p>
        <div class="mt-3 flex flex-wrap gap-1">
          <button
            :for={type <- TaskType.keys()}
            id={"demo-type-#{type}"}
            type="button"
            phx-click="type"
            phx-value-type={type}
            aria-pressed={to_string(@type == type)}
            class={[
              "rounded-lg px-3 py-1.5 text-sm font-medium transition",
              if(@type == type,
                do: "bg-primary text-primary-content",
                else: "bg-base-200 hover:bg-base-300"
              )
            ]}
          >
            {TaskType.label(type)}
          </button>
          <button
            type="button"
            phx-click="restart"
            class="ml-auto rounded-lg px-3 py-1.5 text-sm text-base-content/70 hover:bg-base-200"
          >Restart</button>
        </div>
        <div class="mt-3 rounded-2xl border border-base-300 bg-base-100 p-4">
          <.lifecycle
            type={@type}
            step={@step}
            previous={@previous}
            transitions={@transitions}
            confirming={@confirming}
            simulate_agent?={true}
          />
        </div>
      </section>

      <section
        :for={{kind, blurb, try_this} <- @guides}
        id={"kind-#{kind}"}
        class="mt-12 scroll-mt-20"
      >
        <h2 class="text-lg font-semibold">{Catalog.label(kind)}</h2>
        <dl
          id={"kind-#{kind}-fields"}
          class="mt-2 grid max-w-3xl grid-cols-[7rem_minmax(0,1fr)] gap-x-3 gap-y-1 text-sm"
        >
          <dt class="font-semibold">Kind</dt>
          <dd><code>{kind}</code></dd>
          <dt class="font-semibold">Purpose</dt>
          <dd>{blurb}</dd>
          <dt class="font-semibold">Try this</dt>
          <dd>{try_this}</dd>
        </dl>
        <div class="mt-3 space-y-4">
          <.widget :for={w <- @by_kind[kind] || []} w={w} ctx={@ctx} />
        </div>
      </section>
    </Layouts.app>
    """
  end
end
