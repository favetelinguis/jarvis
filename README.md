# Jarvis

Jarvis is a live task board that coding agents (pi, Codex, GitHub Copilot CLI) and you share.

- **Board.** Agents write goals and tasks through tools, and you watch them change live in the browser. Every task has a **type** (Feature, Research, PR review, Learn) with its own **lifecycle**, drawn as a graph.
- **Widgets.** Goal and task pages are built from visual, interactive widgets (requirement cards, examples you explore, diagrams, architecture tours, comparisons, quizzes, code walkthroughs, review findings) instead of markdown. See the **Design system** page for all of them, playable.
- **Comment on anything.** You can comment on any widget or any part of one. The agent session working on the task receives your comment at its next turn and either updates that widget live or answers in the thread. All sessions, worktrees, and branches of a repository share one board, so a `/design` session in one worktree and an `/impl` session in another work from the same tasks.
- **Two-way.** You can move a task, release a worktree's claim, or comment from the browser. Comments reach the agents concerned at the start of their next turn in all three harnesses; idle sessions are never woken.
- **Presence.** Every pi, Codex, and Copilot CLI session reports whether it is *working* or *waiting for you*, which worktree it runs in, and which task it focuses on.

Built with Elixir, Phoenix LiveView, and Ecto, on SQLite.

## Install

You need [mise](https://mise.jdx.dev) and, for the agents' MCP bridge, `node`. Nothing else: no Erlang, Elixir, Docker, or database.

```bash
mise use -g github:favetelinguis/jarvis
jarvis serve        # http://localhost:4000
```

`jarvis serve` applies pending migrations and serves the board on `127.0.0.1:4000` (`PORT=4100 jarvis serve` for another port). The other commands are `jarvis migrate` and `jarvis version`. The server has no authentication and binds to loopback only: it is a local, single-user tool. Keep one running for all your agents, for example in its own herdr or tmux pane.

**Data.** Everything lives in one file, `jarvis.db`, in the data directory: `$XDG_DATA_HOME/jarvis`, else `~/.local/share/jarvis` on Linux; `~/Library/Application Support/jarvis` on macOS. `JARVIS_DATA_DIR` overrides it. Back up that file to back up Jarvis. Data from the earlier PostgreSQL version is not carried over.

**Agents.** Open **Settings** and click **Install** for pi, Codex, or Copilot CLI (see below). The panel installs the integration files bundled in the release.

**Upgrade.** `mise use -g github:favetelinguis/jarvis@latest`, restart `jarvis serve`, then click **Install** again in Settings: the agents' configuration points into the release's directory, so it must be refreshed after an upgrade. Your data is kept; migrations run on start.

Releases are published for Linux and macOS, x86_64 and aarch64, when a `v*` tag is pushed (`.github/workflows/release.yml`).

## Develop

You need [mise](https://mise.jdx.dev), which installs Erlang 29 and Elixir 1.20 from `mise.toml`.

```bash
cd ~/repos/jarvis
mise install
mise run setup      # deps, MDEx NIF, DB, assets
mise run server     # http://localhost:4000
```

The server uses the same data directory as an installed release; set `JARVIS_DATA_DIR` to keep a development database apart. `MIX_ENV=prod mix release` builds a release in `_build/prod/rel/jarvis`.

Browser live-reload, for developing Jarvis itself, uses inotify when `inotify-tools` is installed and otherwise polls `lib/jarvis_web` and `priv/static` once a second. The dev server logs at `info`, because `debug` would print every SQL query.

## Install it in your agents

On the **Settings** page, the **Integrations** section has one row per agent: whether its CLI is found (with version), whether Jarvis is **Installed**, **Partly installed**, **Not installed**, or **Unreadable**, and **Install** / **Uninstall** buttons. The state is read from the agent's user-level configuration each time; Jarvis only adds, updates, and removes its own entries and never touches a project file.

| Agent | What Install adds |
| --- | --- |
| pi | An explicit extension selection from the package `pi/` in `~/.pi/agent/settings.json`: registers the shared MCP tools, reports presence, and supplies next-turn comments |
| Codex | In `~/.codex/config.toml`, marked `# >>> jarvis` blocks: the board tools as an MCP server (`agent/jarvis-mcp.mjs`) and hooks for presence and comment delivery (`agent/jarvis-hook.mjs`). Also removes the old session-mirror hook |
| Copilot CLI | `mcpServers.jarvis` in `~/.copilot/mcp-config.json`, and presence/comment hooks in `~/.copilot/settings.json` |
| all three | The ten workflow skills in `skills/` copied to `~/.agents/skills/`, one copy for all agents |

All three agents need `node` for the shared MCP server (and the Codex/Copilot hooks). If the server is not at `http://localhost:4000`, it records the URL the panel was opened on. Re-click Install to bring the skills up to date after changing them in this repository. Codex may ask you to trust the new hooks.

Codex and Copilot CLI sessions show on the board, and they receive your comments at the start of their next turn. They are never woken while idle.

The pi package contains a lifecycle-only extension, `pi/extensions/jarvis.ts`. At session start it registers `agent/jarvis-mcp.mjs pi` with pi's built-in MCP support, using the conversation's session ID and working directory. Tools are discovered on demand through codemode or tool search, not duplicated as native extension tools. `/mcp` shows the registered Jarvis server; shell-level `pi mcp list` does not load extensions. Inside this repository the package also loads through `.pi/settings.json`. pi refuses to register the `jarvis` server twice, so if you have clicked **Install** and also work in this repository, remove one of the two (the Install entry in `~/.pi/agent/settings.json`, or `.pi/settings.json`).

To migrate an existing pi installation, re-click **Install** in Settings, then run `/reload` in pi or restart it. The old package-only configuration is shown as partly installed until migrated. The Jarvis footer, `/jarvis` command, and idle comment polling are removed. Codex and Copilot CLI should be restarted after updating their integration. If pi's server runs elsewhere, set `JARVIS_URL` (default `http://localhost:4000`).

### The workflow

Workflows are skills that start only when you name them: `/skill:specify` in pi, `$specify` in Codex, `/specify` in Copilot CLI, followed by the input.

A Feature task moves through **Requirements → Design → Implementation → Review → Done**; the task page shows the graph, where the task came from, and who moves it next.

1. `specify add a live task board`: the agent interviews you and writes the goal and its tasks to Jarvis, each requirement as a card. You confirm each card (or question it on the card), then click **approve requirements**: that move is always yours.
2. `design` in the worktree that should build the task: the agent claims it and sketches it in the code. `design-review` approves the design and moves it on.
3. `impl`, then `impl-review`: the reviewer moves the task to **Done** (or back to Implementation) and leaves its verdict as a comment.

Research, PR review, and Learn tasks have their own skills and lifecycles (`research`, `pr-review`, `learn`).

When an answer from the agent did not land, `eli5` re-explains its last output in plain words. It changes nothing.

The interviewing skills (`specify`, `design`, `design-review`, `research`, `learn`) ask in plain chat in rounds: numbered questions, each with the agent's recommended answer, which you can answer by number. They never use a harness's own question tool.

Several sessions in several worktrees can run at once. Each claims its own task, and the board shows which session works where.

### POC mode

`poc Goal N` (or `poc <what to build>`) skips the strict workflow: the agent builds every task of the goal in one go, moving tasks along their lifecycle with `force_step` (the override that ignores human-only transitions), leaving a comment on each. Use it to see a result fast; use the normal workflow when you want to review each step.

### Tools

| Tool | What it does |
| --- | --- |
| `jarvis_read` | No arguments: the board (goals, tasks with type and step, live sessions). `goal`: a whole goal with its widgets. `goal` + `task`: type, step, the transitions out of it and who moves each, every widget with ids and part ids, comments. |
| `jarvis_goal_save` | Creates a goal (without `goal`) or renames one. |
| `jarvis_task_save` | Creates a task (`title`, `type`: `feature`/`research`/`pr_review`/`learn`) or updates one: `title`, `claim`, `transition` (move along a named transition), `force_step` (jump, for POC runs). |
| `jarvis_widgets` | Adds, updates, moves, deletes widgets in the sections of a goal or task, all ops of a call or none; `judge` records a verdict on a human's free-text quiz answer. |
| `jarvis_catalog` | Every widget kind with its fields, parts, and an example; the sections of each type with recommended widgets. |
| `jarvis_comment` | Leaves a note on a goal or task; `reply_to` answers a comment on a widget, `widget`/`part` start a thread on one. |

Goals are numbered per project and tasks per goal (Goal 3, Task 3.2). Numbers are never reused. Every tool result ends with the link to the page in the browser.

### How a comment on a widget reaches the agent

Every widget and every part carries a comment button. A comment stores its anchor (widget id, part id, and the anchor's text at that moment). The **listening session** of the task (the live session focused on it, else one in its claiming worktree) receives pending comments before responding in its next turn. This applies equally to pi, Codex, and Copilot CLI: comments never start or interrupt a turn. If no session listens, the thread says so, and the comment waits.

Pi supplies plain and anchored comments through its lifecycle extension. Codex uses its `UserPromptSubmit` hook. Copilot uses `userPromptTransformed` and returns `modifiedTransformedPrompt`: config-file `userPromptSubmitted` hooks ignore their output and cannot deliver comments.

### How the project is found

The server resolves each request's working directory with git. Every worktree of a repository has the same git common dir, which identifies the project, and its top level and branch identify the worktree. A directory outside git is a project of its own. A session is identified by its pi session id, so resumed sessions keep their identity.

If the server is down, presence and comment retrieval do not prevent ordinary turns. Board-tool calls return an error asking the agent to have you start Jarvis; mutations are not automatically retried.

All three harnesses use the same six MCP tool definitions. Tool calls carry the actual conversation ID: pi passes it when registering the server, Codex supplies per-call thread metadata, and Copilot supplies `COPILOT_AGENT_SESSION_ID`. Missing identity is reported as a tool error rather than guessing the newest session in the worktree. This keeps simultaneous conversations in one worktree separate.

## Browser

| Page | Shows |
| --- | --- |
| `/` | Projects with task counts and live sessions |
| `/projects/:id` | Goals and matching tasks with All, Unfinished, per-type, and per-step filters; type, step, claim, and focus dots. Live sessions, activity feed |
| `.../goals/:n` | The goal's sections as widgets, its tasks, notes on the goal |
| `.../goals/:n/tasks/:m` | The lifecycle graph and the moves out of the current step, every section as widgets you can comment on, who is listening, release claim, conversation with the agents |
| `/design-system` | Every widget kind with example data, the lifecycle graphs, and the theme, all playable in memory with a simulated agent |
| `/settings` | Integrations (install Jarvis into pi, Codex, Copilot CLI) and the brand colors (primary, secondary, accent): live preview, contrast table, save, reset |

The project-board filter starts at **All** on each visit. **Unfinished** hides tasks in Done; choosing a type offers that type's steps. Goals without matching tasks are hidden, but each visible goal’s progress still includes all its tasks. Filter selection stays in place during live updates; reload or return to the board to reset it.

### Theme

Three brand colors drive the whole UI; each is darkened for light mode and lightened for dark mode until its text reaches a 4.5:1 contrast. Set them on `/settings` to match the company you work for. Mermaid diagrams take the same colors.

Every page updates live through PubSub when an agent or another browser tab changes something.

## HTTP API

The agents identify themselves with these headers. Values are URI-encoded:

- `x-jarvis-cwd`: the session's working directory
- `x-jarvis-session`: the agent session id (optional for Codex and Copilot CLI)
- `x-jarvis-session-name` (optional)
- `x-jarvis-agent` (optional): `pi` (default), `codex`, or `copilot`

Endpoints (`/api` prefix):

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/overview` | Board as markdown |
| POST/GET/PATCH | `/goals`, `/goals/:n` | Create, read, update a goal |
| POST/GET/PATCH | `/goals/:n/tasks`, `/goals/:n/tasks/:m` | Create, read, update a task (`type`, `transition`, `force_step`, `claim`) |
| POST | `/goals/:n/widgets`, `/goals/:n/tasks/:m/widgets` | Apply widget operations (`ops`), all or nothing |
| GET | `/catalog` | The widget catalog as markdown |
| POST | `/goals/:n/comments` | Comment on a goal, or on a task with `task`; `widget`, `part`, `reply_to` for threads |
| POST | `/wake` | The anchored comments this session must hear now (marks them delivered) |
| PUT | `/session` | `{"state": "idle" \| "working" \| "ended"}` |
| POST | `/inbox` | The human's plain comments this session has not seen yet (marks them seen) |

Responses carry `text`, markdown for the model, and `url`, the page in the browser.

## Development

```bash
mise run check    # mix precommit: format, compile --warnings-as-errors, test
```

- Mermaid is vendored in `priv/static/vendor/mermaid.min.js` and loaded on demand by the diagram hook; there is no npm toolchain.
- `mise run setup` runs `bin/fetch-mdex-nif` because MDEx's precompiled-NIF download uses Erlang's `:httpc`, which fails against GitHub on OTP 29. The script fetches the same archive with curl into the rustler_precompiled cache, and checksums are still verified.
- The extension has no build step: pi loads TypeScript through jiti.
