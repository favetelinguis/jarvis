---
name: design-review
description: "Design checkpoint inside a design session - check the task's sketch against its requirements, the project's structure, and simplicity, then refocus"
disable-model-invocation: true
---
Argument: "[what you are worried about]"
Checkpoint for the design session we are in. Focus: the text the human typed after naming this workflow (if empty: the whole sketch of the task being designed).

Read-only: do not modify files. Use the goal's Intent and Glossary, the task's requirements, and this conversation as the record of my intent. Read the task with `jarvis_read`, then the sketch files in its Sketch section, and find every `SKETCH:` comment; use `git status` and `git diff` to see what changed this session. Run the project's check command.

## Tasks in Jarvis

Goals and tasks live in Jarvis, a live board I watch in the browser, never in files. Use its tools:

- `jarvis_read`: no arguments for this project's board; `goal` for a whole goal; `goal` and `task` for a whole task: its type, step, the transitions out of it, every section as widgets with widget ids and part ids, and its comments.
- `jarvis_goal_save` and `jarvis_task_save`: create (no number) or update (with a number) a goal or task: its title, its type (on create), its claim, and its transitions. Sections are not fields: they are widgets.
- `jarvis_widgets`: add, update, move, and delete the widgets in a goal's or task's sections, several operations at once. `jarvis_catalog` lists every widget kind with its fields and each section's recommended kinds.
- `jarvis_comment`: a note I see on the board, for handoffs and decisions to double check; `reply_to` answers a comment on a widget.

Jarvis resolves the project from the working directory: all worktrees and sessions of a repository share one board. Outside a git repository, the directory is its own project.

- Goals are numbered per project and tasks per goal; Jarvis assigns the next free number. Refer to them as Goal N and Task N.M.
- Write every section as widgets, preferring visual ones over prose: each requirement is a `requirement` card (id `R1`…, with its EARS pattern), Examples is an `examples` table, each Glossary term a `glossary_term`, each Decision a `decision`, a Sketch uses `prose`, `diagram`, `architecture`, or `walkthrough`. When you update a widget keep its list items' ids, so my comments, answers, and confirmations stay attached.
- A Feature task is in one step of its lifecycle: Requirements, Design, Implementation, Review, Done. Move it with `jarvis_task_save` `transition`, the moment it changes: "approve design" (/design-review), "requirements question" (/design), "implemented" (/impl), "approve" and "request changes" (/impl-review). "approve requirements" is my decision, after I confirm each requirement card: you never make it, and a task still in Requirements is not yours to design.
- A task belongs to the worktree that claimed it (`claim: true`), shown as its **Worktree:** line. /design claims a task when it takes it up; /impl and /impl-review work only on tasks this worktree claimed.
- My comments from the board arrive at the start of a turn as "New comments from the human in Jarvis"; treat them as my word on that goal or task. A message "Comments on widgets in Jarvis" is me pointing at one widget or part: change that widget with `jarvis_widgets`, or, if it is only a question, answer it with `jarvis_comment` `reply_to`.
- If a Jarvis tool reports that the server is unreachable, stop and tell me; never fall back to files.

Report briefly, skipping any section with nothing to say except implementation blockers, which you always report:

1. **Intent:** restate in a few lines what this task is for. Then say where the sketch has drifted from the requirements or this conversation, or grown beyond them. Call out places where I changed my mind and older parts of the sketch or the task section were not updated.
2. **Coverage and scope:** requirements or Examples rows with no outlined test; outlined tests that serve no requirement; behavior the sketch adds that no requirement states (a missing requirement to take back to me); a Tests or Sketch field in Jarvis that does not match the files; names that stray from the Glossary; a task that has grown past one pull request (name the self-contained part to move into a new task, or say it needs /specify).
3. **Implementation blockers:** anything the implementer could not resolve alone: requirements or `SKETCH:` comments that contradict each other; a test that can only be checked through internals; a sketched part with no place in the project's structure; a needed dependency or module I have not approved; the check command failing. Name the files and the decision needed. If there are none, say "No implementation blockers found."
4. **Fit with the project:** parts placed where the project does not keep that kind of code; new files, modules, helpers, or dependencies where existing ones would do; tests outside the project's test layout or style; conventions in the project's instructions the sketch breaks.
5. **Simplicity:** parts the requirements do not need, shallow wrappers and pass-throughs, interfaces that leak decisions or need a call order, errors pushed onto callers, states as flags, and anything hard to describe in one sentence. Suggest the simpler shape.
6. **Sketch quality:** bodies that were written; major parts with no `SKETCH:` comment; comments too vague to implement from, or that omit an edge case or error the requirements name; detail that belongs to the implementer.
7. **Next:** what to resolve before this task is ready, implementation blockers first, as concrete questions or edits. Put the ones that need my decision to me by the interview protocol below, until none is open.

Be direct and prioritised; a long list of nits hides the real problems. Do not start fixing anything: I will decide and continue the design. When I say the design is approved, move the task with `jarvis_task_save` `transition: "approve design"`.

## Interview protocol

Ask in plain chat, never through a harness's own question tool: these skills run in several harnesses, and pickers push toward canned answers.

- Keep the open decisions as a tree. Each round, ask the whole frontier: every decision whose prerequisites are settled, and none that depends on an answer still open. Recompute it after my answers.
- Format each question as `❓ **Q1** - **<title>**: <body>`, then `➡️ <your recommended answer>` alone on the next line. Word it so "yes" accepts the recommendation; I answer by number ("1 yes, 2 no, because..."). Number on across rounds, so a number always means one question.
- Facts are yours: read the board, the code, the README, and the docs before asking, and never ask what you can find out. Decisions are mine: never answer one yourself and never go on with a guess.
- If I say an answer changes an earlier question, reopen that branch in the next round.
- The interview is done when no open decision is left, not before. Then say what you understood in a few lines and wait for me to confirm we share it; do not act on it, write it down as settled, or move on until I do.
