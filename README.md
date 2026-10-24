# Jarvis

Jarvis is a live task board that coding agents (pi, Codex, GitHub Copilot CLI) and you share.

- **Board.** Agents write goals and tasks through tools, and you watch them change live in the browser. Every task has a **type** (Feature, Research, PR review, Learn) with its own **lifecycle**, drawn as a graph.
- **Widgets.** Goal and task pages are built from visual, interactive widgets (requirement cards, examples you explore, diagrams, architecture tours, comparisons, quizzes, code walkthroughs, review findings) instead of markdown. See the **Design system** page for all of them, playable.
- **Comment on anything.** You can comment on any widget or any part of one. The agent session working on the task is woken within seconds and either updates that widget live or answers in the thread. All sessions, worktrees, and branches of a repository share one board, so a `/design` session in one worktree and an `/impl` session in another work from the same tasks.
- **Two-way.** You can move a task, release a worktree's claim, or comment from the browser. Comments reach the agents concerned at the start of their next turn; pi sessions that are idle are woken.
- **Presence.** Every pi, Codex, and Copilot CLI session reports whether it is *working* or *waiting for you*, which worktree it runs in, and which task it focuses on.

Built with Elixir, Phoenix LiveView, and Ecto, on PostgreSQL in Docker.

## Setup

You need Docker and [mise](https://mise.jdx.dev). mise installs Erlang 29 and Elixir 1.20 from `mise.toml`.

```bash
cd ~/repos/jarvis
mise install
mise run setup      # Postgres in Docker, deps, MDEx NIF, DB, assets
mise run server     # http://localhost:4000
```

Keep one server running for all your agents, for example in its own herdr or tmux pane. To run it in the background, use a systemd user unit:

```ini
# ~/.config/systemd/user/jarvis.service
[Unit]
Description=Jarvis
After=docker.service

[Service]
WorkingDirectory=%h/repos/jarvis
ExecStart=%h/.local/share/mise/shims/mise run server
Restart=on-failure

[Install]
WantedBy=default.target
```

```bash
systemctl --user enable --now jarvis
```

PostgreSQL runs as `jarvis-db-1` on `127.0.0.1:5432` with a named volume (`jarvis-pgdata`), so data survives restarts. The server binds to `127.0.0.1` only and has no authentication: it is a local, single-user tool.

Browser live-reload, for developing Jarvis itself, uses inotify when `inotify-tools` is installed and otherwise polls `lib/jarvis_web` and `priv/static` once a second. The dev server logs at `info`, because `debug` would print every SQL query.

## Install it in your agents

On the **Settings** page, the **Integrations** section has one row per agent: whether its CLI is found (with version), whether Jarvis is **Installed**, **Partly installed**, **Not installed**, or **Unreadable**, and **Install** / **Uninstall** buttons. The state is read from the agent's user-level configuration each time; Jarvis only adds, updates, and removes its own entries and never touches a project file.

| Agent | What Install adds |
| --- | --- |
| pi | The package `pi/` in `~/.pi/agent/settings.json`: board tools, presence, comment wake-ups |
| Codex | In `~/.codex/config.toml`, marked `# >>> jarvis` blocks: the board tools as an MCP server (`agent/jarvis-mcp.mjs`) and hooks for presence and comment delivery (`agent/jarvis-hook.mjs`). Also removes the old session-mirror hook |
| Copilot CLI | `mcpServers.jarvis` in `~/.copilot/mcp-config.json`, and presence/comment hooks in `~/.copilot/settings.json` |
| all three | The nine workflow skills in `skills/` copied to `~/.agents/skills/`, one copy for all agents |

The agents need `node` for Codex and Copilot CLI (the MCP server and hooks are small scripts). If the server is not at `http://localhost:4000`, it records the URL the panel was opened on. Re-click Install to bring the skills up to date after changing them in this repository. Codex may ask you to trust the new hooks.

Codex and Copilot CLI sessions show on the board, and they receive your comments at the start of their next turn. They are never woken while idle.

The pi package in `pi/` contains the extension `pi/extensions/jarvis.ts`: tools, presence, inbox, and the `/jarvis` command. Inside this repository it already loads through `.pi/settings.json`. Pi loads a local package in place, so changes take effect on the next `/reload`. If the server runs elsewhere, set `JARVIS_URL` (default `http://localhost:4000`).

### The workflow

Workflows are skills that start only when you name them: `/skill:specify` in pi, `$specify` in Codex, `/specify` in Copilot CLI, followed by the input.

A Feature task moves through **Requirements → Design → Implementation → Review → Done**; the task page shows the graph, where the task came from, and who moves it next.

1. `specify add a live task board`: the agent interviews you and writes the goal and its tasks to Jarvis, each requirement as a card. You confirm each card (or question it on the card), then click **approve requirements**: that move is always yours.
2. `design` in the worktree that should build the task: the agent claims it and sketches it in the code. `design-review` approves the design and moves it on.
3. `impl`, then `impl-review`: the reviewer moves the task to **Done** (or back to Implementation) and leaves its verdict as a comment.

Research, PR review, and Learn tasks have their own skills and lifecycles (`research`, `pr-review`, `learn`).

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

Every widget and every part carries a comment button. A comment stores its anchor (widget id, part id, and the anchor's text at that moment). While a pi session is idle, the extension polls `/api/wake` every 2 seconds; the **listening session** of the task (the live session focused on it, else one in its claiming worktree) receives the comment as a message and starts a turn. A busy session receives it when its turn ends. If no session listens, the thread says so, and the comment waits. Only pi sessions are woken; Codex and Copilot CLI sessions hear it at their next turn, and the thread says so.

### Commands

- `/jarvis` shows this project's board in the terminal, with its link.

### How the project is found

The server resolves each request's working directory with git. Every worktree of a repository has the same git common dir, which identifies the project, and its top level and branch identify the worktree. A directory outside git is a project of its own. A session is identified by its pi session id, so resumed sessions keep their identity.

If the server is down, the agents keep working: in pi the footer shows `jarvis ○ offline`, and the Jarvis tools of every agent return an error that tells the agent to stop and ask you.

Codex and Copilot CLI start the MCP server in the session's working directory, which is how it finds the project. Their tool calls count as the agent's live session in that worktree.

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
