# Jarvis

Jarvis is a live task board that coding agents and you share, and a mirror of every agent session's context in PostgreSQL.

- **Board.** Agents write goals and tasks through tools, and you watch them change live in the browser. All sessions, worktrees, and branches of a repository share one board, so a `/design` session in one worktree and an `/impl` session in another work from the same tasks.
- **Two-way.** You can move a task, release a worktree's claim, or comment from the browser. Comments reach the agents concerned at the start of their next turn.
- **Presence.** Every pi session reports whether it is *working* or *waiting for you*, which worktree it runs in, and which task it focuses on.
- **Session mirror.** After every turn, the session file of pi (and of Codex, through a hook) is copied into Postgres line by line. You can restore any session from Jarvis and resume it exactly as `/resume` would, even after the local file is gone.

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

Browser live-reload, for developing Jarvis itself, uses inotify when `inotify-tools` is installed and otherwise polls `lib/jarvis_web` and `priv/static` once a second. The dev server logs at `info`, because `debug` would print every SQL query, including the contents of mirrored sessions.

## Use it from pi

The pi package in `pi/` contains:

- **The extension** `pi/extensions/jarvis.ts`: tools, presence, inbox, session mirroring, and the `/jarvis` and `/jarvis-resume` commands.
- **Workflow prompts** `pi/prompts/`: `/specify`, `/design`, `/design-review`, `/impl`, `/impl-review`. These are your workflow, with task files replaced by the Jarvis board.

Inside this repository it already loads through `.pi/settings.json`. To use it in every project, install it once:

```bash
pi install ~/repos/jarvis/pi
```

Pi loads a local package in place, so changes in this repository take effect on the next `/reload`. If the server runs elsewhere, set `JARVIS_URL` (default `http://localhost:4000`).

### Remove the colliding global prompts

Your global prompts in `~/.pi/agent/prompts/` (`specify.md`, `design.md`, `design-review.md`, `impl.md`, `impl-review.md`, installed by the `specify-design-impl-review` skill) have the same names as the Jarvis prompts. They also store tasks as markdown files under `~/.local/state/agent-workflow/`. I left them untouched. Once you switch to Jarvis, uninstall them so each command name has a single meaning, for example by asking pi to *uninstall the specify-design-impl-review workflow prompts*. Keep the skill's global AGENTS.md engineering-practices section; it does not collide.

No other installed extension or skill collides. `provider-footer.ts`, `pi-web-access`, `rpiv-ask-user-question`, `pi-lsp-extension`, and `my_pi` all coexist with Jarvis.

### The workflow

Use the same commands as before:

1. `/specify add a live task board`: the agent interviews you and writes the goal and its tasks to Jarvis. The board shows them as they are written.
2. `/design` in the worktree that should build the next task: the agent claims the task for this worktree, sketches it in the code, and moves it to **ready**.
3. `/impl`, then `/impl-review`: the reviewer moves the task to **done** and leaves its verdict as a comment.

Several sessions in several worktrees can run at once. Each claims its own task, and the board shows which session works where.

### Tools

| Tool | What it does |
| --- | --- |
| `jarvis_read` | No arguments: the board (goals, tasks one line each, live sessions). `goal`: a whole goal. `goal` + `task`: a whole task with its comments. |
| `jarvis_goal_save` | Creates a goal (without `goal`) or updates the fields you pass: `title`, `intent`, `scope`, `glossary`, `decisions`. |
| `jarvis_task_save` | Creates a task in a goal or updates the fields you pass: `title`, `status` (`todo`/`ready`/`done`), `claim` (true claims it for this worktree, false releases it), `intent`, `requirements`, `examples`, `constraints`, `assumptions`, `out_of_scope`, `open_questions`, `sketch`, `tests`. |
| `jarvis_comment` | Leaves a note on a goal or task for you to see on the board. |

Goals are numbered per project and tasks per goal (Goal 3, Task 3.2). Numbers are never reused. Every tool result ends with the link to the page in the browser.

### Commands

- `/jarvis` shows this project's board in the terminal, with its link.
- `/jarvis-resume` lists the project's mirrored sessions (pi and Codex) and restores the one you pick. A pi session opens right away. For a Codex session, it prints the `codex resume` command.

### How the project is found

The server resolves each request's working directory with git. Every worktree of a repository has the same git common dir, which identifies the project, and its top level and branch identify the worktree. A directory outside git is a project of its own. A session is identified by its pi session id, so resumed sessions keep their identity.

If the server is down, pi keeps working: the footer shows `jarvis ○ offline` and the Jarvis tools return an error that tells the agent to stop and ask you. The session mirror catches up on the next turn after the server is back.

## Use it from Codex

Codex has no extension API, but its hooks pass the session file's location on stdin. Append `codex/hooks.toml` to `~/.codex/config.toml`:

```bash
cat ~/repos/jarvis/codex/hooks.toml >> ~/.codex/config.toml
```

After every turn (`Stop`) and at exit (`SessionEnd`), the hook forwards that JSON to Jarvis, which reads the rollout file itself. Codex sessions appear under **Transcripts** on the project page, filed under the right worktree. Restore one from the browser or with `/jarvis-resume`, then run the `codex resume <id>` command shown.

Codex sessions are mirrored and restorable, but Codex has no board tools, presence, or inbox.

## Session mirror

Each harness writes its sessions as JSONL: pi to `~/.pi/agent/sessions/`, Codex to `~/.codex/sessions/`. Jarvis stores one **transcript** per session, keyed by harness and session id. A transcript holds:

- **every line, as exact bytes**, in order. This is the resume context. Restoring writes these bytes back to the original path, which reproduces the file exactly.
- **a harness-neutral reading of each line**: role (`user`, `assistant`, `tool_call`, `tool_result`, `system`, `meta`), text, and time. The transcript page shows this reading, with the same layout for pi and Codex.

Two rules keep the mirror exact:

- **Sync is incremental and safe to repeat.** Jarvis remembers how far it read and the hash of the last line it read. Each sync reads only new complete lines and leaves a half-written line for the next sync. If a file was rewritten rather than appended to, for example by pi's session migration, Jarvis reads it again from the start.
- **Restore never destroys data.** A file that already holds the transcript (or the transcript plus newer lines) is left alone. A file with other content is moved to `<path>.jarvis-backup-<unix time>` before the transcript is written.

Jarvis only reads and writes `.jsonl` files under the transcript roots. By default these are `~/.pi/agent/sessions` (or `PI_CODING_AGENT_SESSION_DIR`) and `~/.codex/sessions` (or `$CODEX_HOME/sessions`). Override them with `JARVIS_TRANSCRIPT_ROOTS=/a:/b`.

A session restores into the harness that wrote it. Converting a pi session into a Codex session, or the reverse, is not supported, because each harness's context carries its own system prompt and tool protocol.

## Browser

| Page | Shows |
| --- | --- |
| `/` | Projects with task counts and live sessions |
| `/projects/:id` | Goals and matching tasks with All, Unfinished, Todo, Ready, and Done filters; status, claim, open-questions badge, and focus dots. Live sessions, mirrored transcripts, activity feed |
| `.../goals/:n` | Intent, Scope, Glossary, Decisions, tasks, notes on the goal |
| `.../goals/:n/tasks/:m` | Every section, status switch, release claim, conversation with the agents |
| `/transcripts/:id` | The session in harness-neutral form, tool calls on demand, **Restore session** |

The project-board filter starts at **All** on each visit. **Unfinished** includes todo and ready tasks. Goals without matching tasks are hidden, but each visible goal’s progress still includes all its tasks. Filter selection stays in place during live updates; reload or return to the board to reset it.

Every page updates live through PubSub when an agent or another browser tab changes something.

## HTTP API

The pi extension identifies itself with three headers. Values are URI-encoded:

- `x-jarvis-cwd`: the session's working directory
- `x-jarvis-session`: the pi session id
- `x-jarvis-session-name` (optional)

Endpoints (`/api` prefix):

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/overview` | Board as markdown |
| POST/GET/PATCH | `/goals`, `/goals/:n` | Create, read, update a goal |
| POST/GET/PATCH | `/goals/:n/tasks`, `/goals/:n/tasks/:m` | Create, read, update a task |
| POST | `/goals/:n/comments` | Comment on a goal, or on a task with `task` in the body |
| PUT | `/session` | `{"state": "idle" \| "working" \| "ended"}` |
| POST | `/inbox` | The human's comments this session has not seen yet (marks them seen) |
| GET | `/transcripts` | The project's mirrored sessions |
| POST | `/transcripts/:id/restore` | Write the session file back; returns `status`, `path`, `backup`, `command` |
| POST | `/transcripts/sync?harness=pi\|codex` | No identity headers. Body: `session_id`, `transcript_path`, `cwd` (a Codex hook's stdin as is) |

Responses carry `text`, markdown for the model, and `url`, the page in the browser.

## Development

```bash
mise run check    # mix precommit: format, compile --warnings-as-errors, test
```

- `mise run setup` runs `bin/fetch-mdex-nif` because MDEx's precompiled-NIF download uses Erlang's `:httpc`, which fails against GitHub on OTP 29. The script fetches the same archive with curl into the rustler_precompiled cache, and checksums are still verified.
- The extension has no build step: pi loads TypeScript through jiti.
