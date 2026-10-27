defmodule JarvisWeb.GuideLive do
  @moduledoc """
  The Guide: how goals, tasks, steps, transitions, claims, and the workflows
  fit together, and how a task of each type goes from its first step to Done.
  Always in English; the board language only steers what agents write.

  Lifecycle graphs, transition cards, and who makes each move in an example
  flow come from `TaskType` at render time. Everything else is written here by
  hand, and the tests replay each example flow against `TaskType`.
  """
  use JarvisWeb, :live_view

  alias Jarvis.Planning.TaskType

  import JarvisWeb.WidgetComponents, only: [lifecycle_graph: 1]

  @typedoc """
  One step of an example flow. `say` is the prompt, a workflow name and its
  input (`nil` when you only act on the board); `board` is what you do there
  (`nil` for nothing). `move` names the transition the step ends with, out of
  the step the flow is in; the page says who makes it, so the text never does.
  """
  @type flow_step :: %{
          say: String.t() | nil,
          agent: String.t(),
          board: String.t() | nil,
          move: String.t() | nil
        }

  @concepts [
    {"goal", "Goal",
     "A goal is a collection of tasks that together deliver one outcome. Its Intent, Scope, Glossary, and Decisions hold for every task in it."},
    {"task", "Task",
     "One piece of work in a goal: a feature slice, a question, a pull request to review, or a topic to learn. Its sections are widgets you can comment on."},
    {"task-type", "Task type",
     "Feature, Research, PR review, or Learn, chosen when the task is created and never changed. A task's type decides its steps and transitions, and the sections on its page."},
    {"step", "Step",
     "Where a task stands in its lifecycle, such as Design for a Feature. A task is in exactly one step."},
    {"transition", "Transition",
     "A named move from one step to another, forward or back, such as *approve requirements* or *request changes*. Some have a condition that must hold first."},
    {"mover", "Mover",
     "Who makes a transition: you, with a button on the task page, or the agent, in the workflow that works the step. No agent can make your move, even when you ask in the chat."},
    {"turn", "Whose turn",
     "Who acts next in a task: **your turn** (a decision on the task page), the **agent's turn** (a named command in a named worktree), or nobody's. The task page and the board always show it."},
    {"handoff", "Handoff",
     "An agent gives the turn to you inside a step, without leaving it. Only then is your decision due, for example after `design` hands Design over."},
    {"turn-report", "Turn report",
     "What one agent turn changed on the board: each widget before and after, the agent's reason, and what it needs from you."},
    {"out-of-date", "Out of date",
     "Something built on a part that changed since, such as evidence after a requirement was reworded. It is marked until the agent writes it again."},
    {"evidence", "Evidence",
     "What an agent records before it hands a Feature to you: the check command and result, each requirement with its test, and a review report."},
    {"claim", "Claim",
     "A worktree's hold on a Feature task, shown as the task's **Worktree** line. Only the claiming worktree builds and reviews the task."},
    {"worktree", "Worktree",
     "A checkout of the repository on its own branch; all worktrees of a repository share one board. Each can work on a different task."},
    {"session", "Session",
     "One conversation with a coding agent (pi, Codex, or Copilot CLI) running in a worktree. The board shows each live session and the task it focuses on."}
  ]

  @claims [
    {"claim-same-worktree", "Feature", "Another harness, same worktree", "Any",
     "No release needed: the new session carries on with the task."},
    {"claim-design", "Feature", "Another worktree", "Design",
     "`design` there claims the task and replaces the old claim."},
    {"claim-impl", "Feature", "Another worktree", "Implementation or Acceptance",
     "`impl` and `impl-review` work only on tasks their worktree claimed, so they do not take it up there."},
    {"claim-unclaimed", "Research, PR review, or Learn", "Anything", "Any",
     "There is no claim to release: these tasks are never claimed."}
  ]

  # Upstream changes and what they make out of date (see Planning's cascades).
  @cascades [
    {"cascade-requirement", "A requirement is reworded, added, or removed",
     "Its confirmation is cleared; the task's evidence and review report",
     "approve design, implemented, accept"},
    {"cascade-head", "A re-review round finds a new head", "The quiz and the findings",
     "Nothing"},
    {"cascade-dig", "You choose dig deeper", "The recommendation", "Nothing"},
    {"cascade-check", "You answer a Learn check question wrong",
     "The explanation widget the question tests, if it names one", "Nothing"}
  ]

  @intros [
    feature:
      "A change to the code, from requirements you confirm to a reviewed implementation. One Feature task is one pull request.",
    research:
      "A question investigated with the agent; the findings are comparisons, diagrams, and sources you weigh.",
    pr_review:
      "Someone else's pull request: the agent explains it, quizzes you, and records findings. The verdict is yours.",
    learn:
      "A topic the agent explains with diagrams and walkthroughs, then checks you understood with a quiz."
  ]

  @flows [
    feature: [
      %{
        say: "specify add a live task board",
        agent:
          "Interviews you and writes the goal and its tasks, each requirement as a card. Then it hands over.",
        board: "Confirm each requirement card, or question it on the card.",
        move: "approve requirements"
      },
      %{
        say: "design",
        agent:
          "Claims the task and sketches it with you. A review in a fresh context checks it; then it hands over.",
        board: "Read the review report, then write what the sketch should change.",
        move: "request design changes"
      },
      %{
        say: "design",
        agent: "Reads your comment, amends the sketch, reviews it again, and hands Design over.",
        board: "Read the turn report: each change with its reason.",
        move: "approve design"
      },
      %{
        say: "impl",
        agent:
          "Writes the tests, builds the task, has it reviewed in a fresh context, and records the evidence.",
        board: nil,
        move: "implemented"
      },
      %{
        say: nil,
        agent: "Waits for you.",
        board: "Weigh the evidence and the review; write what is still wrong.",
        move: "request changes"
      },
      %{
        say: "impl",
        agent: "Fixes what your comment names and records new evidence.",
        board: nil,
        move: "implemented"
      },
      %{
        say: nil,
        agent: "Waits for you.",
        board: "Weigh the new evidence.",
        move: "accept"
      }
    ],
    research: [
      %{
        say: "research which job queue fits our workload",
        agent:
          "Writes the question and its context, and asks what the answer is for. Then it hands over.",
        board: "Check that the question is the one you want answered.",
        move: "approve question"
      },
      %{
        say: "research Task 3.1",
        agent: "Investigates and writes findings, sources, and a recommendation.",
        board: nil,
        move: "findings ready"
      },
      %{
        say: nil,
        agent: "Waits for you.",
        board: "Change the comparison's weights; write why the recommendation does not hold up.",
        move: "dig deeper"
      },
      %{
        say: "research Task 3.1",
        agent: "Investigates further and rewrites the recommendation, which was out of date.",
        board: nil,
        move: "findings ready"
      },
      %{
        say: nil,
        agent: "Waits for you.",
        board: "Weigh the findings again.",
        move: "accept"
      }
    ],
    pr_review: [
      %{
        say: "pr-review https://github.com/acme/app/pull/42",
        agent: "Reads the pull request, its discussion, and the code around the diff.",
        board: nil,
        move: "start explanation"
      },
      %{
        say: nil,
        agent:
          "Explains the change: background, intuition, a walkthrough of the code, and a quiz. Then it hands over.",
        board: "Comment on any part you do not follow.",
        move: "ready for the quiz"
      },
      %{
        say: "pr-review Task 2.1",
        agent: "Records findings with severity and suggested changes.",
        board: "Answer the quiz first, or press Skip quiz.",
        move: "findings ready"
      },
      %{
        say: "pr-review Task 2.1",
        agent: "Matches your view against its findings.",
        board: "Write your view, then mark each finding Agree, Disagree, or Fixed.",
        move: "give verdict"
      }
    ],
    learn: [
      %{
        say: "learn how Phoenix PubSub works",
        agent: "Asks what you already know and writes the topic and its terms.",
        board: nil,
        move: "explain"
      },
      %{
        say: nil,
        agent:
          "Explains it with a diagram and a walkthrough, writes the check quiz, and hands over.",
        board: "Comment on any part you do not follow.",
        move: "check understanding"
      },
      %{
        say: nil,
        agent: "Waits for you.",
        board: "Answer the quiz; two answers are wrong. Write what is still unclear.",
        move: "gaps found"
      },
      %{
        say: "learn Task 4.2",
        agent: "Revises the explanations your wrong answers made out of date, and hands over.",
        board: "Read the turn report.",
        move: "check understanding"
      },
      %{
        say: nil,
        agent: "Waits for you.",
        board: "Answer the quiz again, every question right.",
        move: "passed"
      }
    ]
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Guide")}
  end

  @impl true
  def render(assigns) do
    types = for type <- TaskType.keys(), do: {type, anchor(type)}

    toc =
      [
        {"#concepts", "Concepts"},
        {"#claims", "Claims and sessions"},
        {"#comments", "Comments"},
        {"#gates", "Gate quizzes"},
        {"#turns", "Whose turn"},
        {"#turn-reports", "Turn reports"},
        {"#evidence", "Evidence"},
        {"#out-of-date", "Out of date"},
        {"#section-owners", "Steps own sections"}
      ] ++
        for({type, a} <- types, do: {"##{a}", TaskType.label(type)}) ++
        [{"#other-workflows", "Other workflows"}]

    assigns =
      assign(assigns,
        concepts: @concepts,
        claims: @claims,
        cascades: @cascades,
        types: types,
        toc: toc
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      theme_css={@theme_css}
      form={:explanation}
      crumbs={[{"Guide", ~p"/guide"}]}
    >
      <header class="max-w-3xl">
        <h1 class="text-2xl font-semibold tracking-tight">Guide</h1>
        <p class="mt-2 text-base-content/70">
          How goals, tasks, and their steps fit together. How you and the agents take each task type to Done:
          what you type, what the agent does, and what you do on the board.
        </p>
        <nav id="guide-nav" class="mt-4 flex flex-wrap gap-1.5 text-sm" aria-label="On this page">
          <a
            :for={{href, label} <- @toc}
            href={href}
            class="rounded-full bg-base-200 px-3 py-1 transition hover:bg-primary/10"
          >
            {label}
          </a>
        </nav>
      </header>

      <section id="concepts" class="mt-10 scroll-mt-20">
        <h2 class="text-lg font-semibold">Concepts</h2>
        <dl class="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <div
            :for={{id, term, text} <- @concepts}
            id={"concept-#{id}"}
            class="rounded-2xl border border-base-300 bg-base-100 p-4"
          >
            <dt class="font-semibold">{term}</dt>
            <dd class="mt-1 text-sm text-base-content/70"><.markdown text={text} /></dd>
          </div>
        </dl>
      </section>

      <section id="claims" class="mt-10 scroll-mt-20">
        <h2 class="text-lg font-semibold">Claims and sessions</h2>
        <div class="mt-1 max-w-3xl text-sm text-base-content/70">
          <.markdown text="A claim belongs to one worktree, not to a session or a harness. So different worktrees can work on different tasks at the same time. Every session in the claiming worktree can work on the task, in any harness. Only `design` and `poc` claim a task; you release a claim with **Release claim** on the task page." />
        </div>
        <div class="mt-3 overflow-x-auto rounded-2xl border border-base-300 bg-base-100">
          <table class="w-full text-left text-sm">
            <thead class="bg-base-200/60 text-xs uppercase tracking-wide text-base-content/70">
              <tr>
                <th class="px-4 py-2 font-medium">Task type</th>
                <th class="px-4 py-2 font-medium">You switch to</th>
                <th class="px-4 py-2 font-medium">Step</th>
                <th class="px-4 py-2 font-medium">What happens</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={{id, type, switch, step, outcome} <- @claims}
                id={id}
                class="border-t border-base-300 align-top"
              >
                <td class="px-4 py-2">{type}</td>
                <td class="px-4 py-2">{switch}</td>
                <td class="px-4 py-2">{step}</td>
                <td class="px-4 py-2"><.markdown text={outcome} /></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <div class="mt-10 grid gap-6 md:grid-cols-2">
        <section id="comments" class="scroll-mt-20">
          <h2 class="text-lg font-semibold">Comments</h2>
          <p class="mt-1 text-sm text-base-content/70">
            Every widget, and every part of one, has a comment button. Your comment reaches the
            task's listening session at the start of its next turn. That is the live session focused on
            the task, or else one in the claiming worktree. An idle session is never woken by a
            comment. When no session listens, the comment waits, and the thread says so.
          </p>
        </section>
        <section id="gates" class="scroll-mt-20">
          <h2 class="text-lg font-semibold">Gate quizzes</h2>
          <p class="mt-1 text-sm text-base-content/70">
            A quiz in gate mode names a transition, such as <em>passed</em> in a Learn task.
            It blocks the transition it names until every question is answered correctly.
            Until then, the move on the task page says why it is blocked.
          </p>
        </section>
      </div>

      <div class="mt-10 grid gap-6 md:grid-cols-2">
        <section id="turns" class="scroll-mt-20">
          <h2 class="text-lg font-semibold">Whose turn</h2>
          <div class="mt-1 text-sm text-base-content/70">
            <.markdown text="Every step gives the turn to someone when it begins; each type's table below says who. On your turn the task page lists each decision open to you, and what each still lacks. On the agent's turn it names the command and the worktree. It also says whether a session works on it now. When an agent's work in a step is ready, it hands the step over and the turn is yours. Sending work back without leaving the step, as *request design changes* does, gives the turn back to the agent. In a PR review's Quiz, answering every question or pressing **Skip quiz** gives the turn to the agent. Your buttons work on either turn. Each move you make reaches the listening session at its next turn, with your comment. Jarvis never wakes a session. The filter **Your turn** on the project board shows only tasks waiting for you." />
          </div>
        </section>
        <section id="turn-reports" class="scroll-mt-20">
          <h2 class="text-lg font-semibold">Turn reports</h2>
          <div class="mt-1 text-sm text-base-content/70">
            <.markdown text="After a turn changes the board, a collapsed turn report appears at the top of the task page. Open it to see each widget the turn added, changed, or removed, with its content before and after. For lists it names the items added, removed, or changed. Each change shows the agent's reason, or *No reason given*. The report ends with what the agent needs from you. The widgets it changed are marked. Press **Mark turn as read** to move the report to the history **Turns**. A goal page shows reports of changes to the goal and the tasks created in it. Changes to code files never appear; git shows them." />
          </div>
        </section>
        <section id="evidence" class="scroll-mt-20">
          <h2 class="text-lg font-semibold">Evidence at a handoff</h2>
          <div class="mt-1 text-sm text-base-content/70">
            <.markdown text="A Feature reaches your gate only with evidence you can check. Jarvis checks what the evidence says; it runs nothing itself." />
          </div>
          <ul class="mt-2 space-y-1 text-sm">
            <li id="evidence-design">
              <strong>design</strong>
              hands Design over only with a review report in the section Review.
              You can approve the design whatever the review found.
            </li>
            <li id="evidence-impl">
              <strong>implemented</strong>
              waits for evidence: the check passed, every requirement has a
              passing test, and a review report exists.
            </li>
          </ul>
        </section>
        <section id="section-owners" class="scroll-mt-20">
          <h2 class="text-lg font-semibold">Steps own sections</h2>
          <div class="mt-1 text-sm text-base-content/70">
            <.markdown text="An agent writes a task's sections only while its step owns them; each type's table below lists them. In Acceptance no section is the agent's, so what you weigh cannot change under you. Your own actions on widgets are never limited. Only `poc` may jump a task to any step, with `force_step`, and only in a goal marked POC." />
          </div>
        </section>
      </div>

      <section id="out-of-date" class="mt-10 scroll-mt-20">
        <h2 class="text-lg font-semibold">Out of date</h2>
        <p class="mt-1 max-w-3xl text-sm text-base-content/70">
          A change upstream marks what builds on it Out of date, with what changed and a link to it.
          The mark goes when the agent writes the widget again.
        </p>
        <div class="mt-3 overflow-x-auto rounded-2xl border border-base-300 bg-base-100">
          <table class="w-full text-left text-sm">
            <thead class="bg-base-200/60 text-xs uppercase tracking-wide text-base-content/70">
              <tr>
                <th class="px-4 py-2 font-medium">Change upstream</th>
                <th class="px-4 py-2 font-medium">Out of date</th>
                <th class="px-4 py-2 font-medium">Blocks</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={{id, change, stale, blocks} <- @cascades}
                id={id}
                class="border-t border-base-300 align-top"
              >
                <td class="px-4 py-2">{change}</td>
                <td class="px-4 py-2">{stale}</td>
                <td class="px-4 py-2">{blocks}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <.type_section :for={{type, a} <- @types} type={type} anchor={a} />

      <section id="other-workflows" class="mt-12 scroll-mt-20">
        <h2 class="text-lg font-semibold">Other workflows</h2>
        <div class="mt-3 grid gap-3 md:grid-cols-2">
          <div id="workflow-poc" class="rounded-2xl border border-base-300 bg-base-100 p-4">
            <p class="font-semibold">
              <code data-role="prompt" class="rounded bg-base-200 px-1.5 py-0.5">poc Goal 3</code>
            </p>
            <p class="mt-2 text-sm text-base-content/70">
              Builds every task of a goal in one go, in this worktree, so you see a result fast.
              It moves the tasks past your transitions with <code>force_step</code>.
              That works only in a goal marked POC. It leaves a comment on every task it builds.
              The goal stays marked POC until you click <strong>Mark reviewed</strong>
              on the goal page.
            </p>
          </div>
          <div id="workflow-eli5" class="rounded-2xl border border-base-300 bg-base-100 p-4">
            <p class="font-semibold">
              <code data-role="prompt" class="rounded bg-base-200 px-1.5 py-0.5">eli5</code>
            </p>
            <p class="mt-2 text-sm text-base-content/70">
              When an answer from the agent did not land:
              re-explains its last answer in plain words, with one everyday picture.
              It changes nothing, neither files nor the board.
            </p>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :type, :atom, required: true
  attr :anchor, :string, required: true

  defp type_section(assigns) do
    {steps, _} =
      Enum.map_reduce(Keyword.fetch!(@flows, assigns.type), TaskType.first_step(assigns.type), fn
        %{move: nil} = s, step ->
          {{s, nil}, step}

        s, step ->
          case TaskType.find_transition(assigns.type, step, s.move) do
            nil -> {{s, :unknown}, step}
            t -> {{s, t}, t.to}
          end
      end)

    assigns =
      assign(assigns,
        intro: Keyword.fetch!(@intros, assigns.type),
        transitions: TaskType.transitions(assigns.type),
        steps: Enum.with_index(steps, 1)
      )

    ~H"""
    <section id={@anchor} class="mt-12 scroll-mt-20">
      <h2 class="flex items-center gap-2 text-lg font-semibold">
        <.icon name={TaskType.icon(@type)} class="size-5 text-primary" />
        {TaskType.label(@type)}
      </h2>
      <p class="mt-1 max-w-3xl text-sm text-base-content/70">{@intro}</p>

      <div class="mt-3 rounded-2xl border border-base-300 bg-base-100 p-4">
        <.lifecycle_graph type={@type} prefix={"#{@anchor}-"} />
        <div class="mt-3 grid gap-2 md:grid-cols-3">
          <.transition_card :for={t <- @transitions} type={@type} anchor={@anchor} t={t} />
        </div>
      </div>

      <div class="mt-3 overflow-x-auto rounded-2xl border border-base-300 bg-base-100">
        <table id={"#{@anchor}-steps"} class="w-full text-left text-sm">
          <thead class="bg-base-200/60 text-xs uppercase tracking-wide text-base-content/70">
            <tr>
              <th class="px-4 py-2 font-medium">Step</th>
              <th class="px-4 py-2 font-medium">Turn when it begins</th>
              <th class="px-4 py-2 font-medium">An agent writes</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={{key, label, _} <- TaskType.steps(@type)}
              id={"#{@anchor}-steps-#{key}"}
              class="border-t border-base-300 align-top"
            >
              <td class="px-4 py-2 font-medium">{label}</td>
              <td data-role="turn" class="px-4 py-2">{turn_text(TaskType.start_turn(@type, key))}</td>
              <td data-role="owns" class="px-4 py-2">
                {case TaskType.owned_sections(@type, key) do
                  [] -> "Nothing"
                  keys -> Enum.map_join(keys, ", ", &TaskType.section_label(@type, &1))
                end}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        :if={@type == :pr_review}
        id="your-view"
        class="mt-3 rounded-2xl border border-base-300 bg-base-100 p-4"
      >
        <p class="font-semibold">Your view</p>
        <p class="mt-1 max-w-3xl text-sm text-base-content/70">
          In Findings you first write your own concerns, one per line, or skip.
          The first round's findings stay hidden until then, so you review yourself instead of only agreeing.
          Turn reports name changes to them without showing them.
          The agent then matches them: each finding says <em>You saw this too</em>
          or <em>Only the agent</em>,
          and each concern no finding covers says <em>Only you</em>. You can change any match.
          Findings of later rounds show at once.
        </p>
      </div>

      <div :if={@type == :feature} class="mt-3 grid gap-3 md:grid-cols-2">
        <div id="scenario-parallel" class="rounded-2xl border border-base-300 bg-base-100 p-4">
          <p class="font-semibold">Two tasks at once</p>
          <ol class="mt-2 list-decimal space-y-1 pl-5 text-sm text-base-content/70">
            <li>
              In worktree <strong>app</strong>: <.prompt text="design Task 1.1" />
              claims Task 1.1 there.
            </li>
            <li>
              In worktree <strong>app-search</strong>: <.prompt text="design Task 1.2" />
              claims Task 1.2 there.
            </li>
            <li>
              Each worktree runs <.prompt text="impl" /> and <.prompt text="impl-review" />
              on its own task; the board shows both sessions and where each works.
            </li>
          </ol>
        </div>
        <div id="scenario-harness-switch" class="rounded-2xl border border-base-300 bg-base-100 p-4">
          <p class="font-semibold">Switch harness, keep the claim</p>
          <ol class="mt-2 list-decimal space-y-1 pl-5 text-sm text-base-content/70">
            <li>
              In pi, in worktree <strong>app</strong>: <.prompt text="design Task 1.1" />
              claims the task and sketches it.
            </li>
            <li>In Codex, in the same worktree: <.prompt text="impl Task 1.1" /> builds it.</li>
            <li>
              No release: the claim is the worktree's, so the Codex session takes the task up at once.
            </li>
          </ol>
        </div>
      </div>

      <h3 class="mt-6 font-semibold">Example flow</h3>
      <div class="mt-2 hidden grid-cols-[2rem_1fr_1fr_1fr] gap-3 px-3 text-xs uppercase tracking-wide text-base-content/70 md:grid">
        <span></span><span>You type</span><span>The agent</span><span>On the board</span>
      </div>
      <ol id={"#{@anchor}-flow"} class="mt-1 space-y-2">
        <li
          :for={{{s, t}, n} <- @steps}
          id={"#{@anchor}-flow-#{n}"}
          data-move={s.move}
          class="grid gap-x-3 gap-y-1 rounded-xl border border-base-300 bg-base-100 p-3 text-sm md:grid-cols-[2rem_1fr_1fr_1fr]"
        >
          <span class="grid size-6 place-items-center rounded-full bg-primary font-mono text-xs text-primary-content">
            {n}
          </span>
          <div data-role="say">
            <.prompt :if={s.say} text={s.say} />
            <span :if={!s.say} class="italic text-base-content/70">You type nothing.</span>
          </div>
          <p data-role="agent">{s.agent}</p>
          <p data-role="board" class={!s.board && "italic text-base-content/70"}>
            {s.board || "Nothing."}
          </p>
          <p
            :if={t}
            data-role="mover"
            class="flex items-center gap-1.5 text-xs text-base-content/70 md:col-start-2 md:col-span-3"
          >
            <%= case t do %>
              <% :unknown -> %>
                No move {s.move} out of this step.
              <% %{mover: :human} -> %>
                <.icon name="hero-user" class="size-4" />
                <span>You click <strong>{t.name}</strong>
                on the task page; it moves to {TaskType.step_label(@type, t.to)}.</span>
              <% %{mover: :agent} -> %>
                <.icon name="hero-cpu-chip" class="size-4" />
                <span><code>{workflow(t)}</code> moves it to {TaskType.step_label(@type, t.to)}.</span>
            <% end %>
          </p>
        </li>
      </ol>
    </section>
    """
  end

  attr :type, :atom, required: true
  attr :anchor, :string, required: true
  attr :t, :map, required: true

  defp transition_card(assigns) do
    ~H"""
    <div
      id={"#{@anchor}-transition-#{String.replace(@t.name, " ", "-")}"}
      class="rounded-xl border border-base-300 p-3"
    >
      <div class="flex items-center gap-2">
        <.icon
          name={if @t.mover == :human, do: "hero-user", else: "hero-cpu-chip"}
          class="size-4 text-base-content/70"
        />
        <p class="font-medium">{@t.name}</p>
        <span class="ml-auto text-xs text-base-content/70">
          <span data-role="from">{TaskType.step_label(@type, @t.from)}</span>
          → <span data-role="to">{TaskType.step_label(@type, @t.to)}</span>
        </span>
      </div>
      <p data-role="mover" data-mover={@t.mover} class="mt-1 text-xs text-base-content/70">
        <%= if @t.mover == :human do %>
          You click it on the task page; no agent can.
        <% else %>
          <code class="rounded bg-base-200 px-1">{workflow(@t)}</code> moves it.
        <% end %>
      </p>
      <p :if={@t[:comment]} data-role="comment" class="mt-1 text-xs font-medium">
        Needs your comment on what to change.<span :if={@t[:creates_task]}> It becomes a new task in Requirements.</span>
      </p>
      <p :for={c <- @t[:conditions] || []} data-role="condition" class="mt-1 text-xs">
        <span class="rounded bg-warning/30 px-1.5 py-0.5 text-base-content">
          {condition(c)}
        </span>
      </p>
    </div>
    """
  end

  attr :text, :string, required: true

  defp prompt(assigns) do
    ~H"""
    <code data-role="prompt" class="rounded bg-base-200 px-1.5 py-0.5">{@text}</code>
    """
  end

  # A condition without a sentence here must crash the page, not vanish from it.
  defp condition(:requirements_confirmed), do: "Only when every requirement card is confirmed."
  defp condition(:review_current), do: "Only when the review report is not out of date."

  defp condition(:evidence),
    do: "Only with evidence: check passed, a passing test per requirement, a review."

  defp condition(:evidence_current),
    do: "Only when the evidence and the review are not out of date."

  defp condition(:quiz_answered),
    do: "Only when you answered every quiz question, or skipped the quiz."

  defp turn_text({:agent, command, true}),
    do: "The agent's (#{workflow(%{command: command})}); it hands the step over to you"

  defp turn_text({:agent, command, false}), do: "The agent's (#{workflow(%{command: command})})"
  defp turn_text(:human), do: "Yours"
  defp turn_text(:none), do: "Nobody's"

  defp workflow(t), do: String.trim_leading(t.command, "/")

  defp anchor(type), do: type |> Atom.to_string() |> String.replace("_", "-")

  @doc "The Guide's path at the section for a task type, e.g. `/guide#pr-review`."
  @spec path(TaskType.key()) :: String.t()
  def path(type), do: ~p"/guide" <> "#" <> anchor(type)
end
