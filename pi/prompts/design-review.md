---
description: Design checkpoint inside a design session - check the task's sketch against its requirements, the project's structure, and simplicity, then refocus
argument-hint: "[what you are worried about]"
---
Checkpoint for the design session we are in. Focus: $ARGUMENTS (if empty: the whole sketch of the task being designed).

Read-only: do not modify files. Use the goal's Intent and Glossary, the task's requirements, and this conversation as the record of my intent. Read the task with `jarvis_read`, then the sketch files in its Sketch field, and find every `SKETCH:` comment; use `git status` and `git diff` to see what changed this session. Run the project's check command.

## Tasks in Jarvis

Goals and tasks live in Jarvis, a live board I watch in the browser, never in files. Use its tools:

- `jarvis_read`: no arguments for this project's board; `goal` for a whole goal; `goal` and `task` for a whole task with its comments.
- `jarvis_goal_save` and `jarvis_task_save`: create (no number) or update (with a number) a goal or task. Only the fields you pass change.
- `jarvis_comment`: a note I see on the board, for handoffs and decisions to double check.

Jarvis resolves the project from the working directory: all worktrees and sessions of a repository share one board. Outside a git repository, the directory is its own project.

- Goals are numbered per project and tasks per goal; Jarvis assigns the next free number. Refer to them as Goal N and Task N.M.
- A task's status is `[todo]` (requirements written), `[ready]` (sketch written, awaiting implementation), or `[done]` (implemented and reviewed). Set it with `jarvis_task_save` the moment it changes.
- A task belongs to the worktree that claimed it (`claim: true`), shown as its **Worktree:** line. /design claims a task when it takes it up; /impl and /impl-review work only on tasks this worktree claimed.
- My comments from the board arrive at the start of a turn as "New comments from the human in Jarvis"; treat them as my word on that goal or task.
- If a Jarvis tool reports that the server is unreachable, stop and tell me; never fall back to files.

Report briefly, skipping any section with nothing to say except implementation blockers, which you always report:

1. **Intent:** restate in a few lines what this task is for. Then say where the sketch has drifted from the requirements or this conversation, or grown beyond them. Call out places where I changed my mind and older parts of the sketch or the task section were not updated.
2. **Coverage and scope:** requirements or Examples rows with no outlined test; outlined tests that serve no requirement; behavior the sketch adds that no requirement states (a missing requirement to take back to me); a Tests or Sketch field in Jarvis that does not match the files; names that stray from the Glossary; a task that has grown past one pull request (name the self-contained part to move into a new `[todo]` task, or say it needs /specify).
3. **Implementation blockers:** anything the implementer could not resolve alone: requirements or `SKETCH:` comments that contradict each other; a test that can only be checked through internals; a sketched part with no place in the project's structure; a needed dependency or module I have not approved; the check command failing. Name the files and the decision needed. If there are none, say "No implementation blockers found."
4. **Fit with the project:** parts placed where the project does not keep that kind of code; new files, modules, helpers, or dependencies where existing ones would do; tests outside the project's test layout or style; conventions in the project's instructions the sketch breaks.
5. **Simplicity:** parts the requirements do not need, shallow wrappers and pass-throughs, interfaces that leak decisions or need a call order, errors pushed onto callers, states as flags, and anything hard to describe in one sentence. Suggest the simpler shape.
6. **Sketch quality:** bodies that were written; major parts with no `SKETCH:` comment; comments too vague to implement from, or that omit an edge case or error the requirements name; detail that belongs to the implementer.
7. **Next:** the 2 to 4 most valuable things to resolve before this task is ready, implementation blockers first, as concrete questions or edits. Ask the ones that need my decision with a structured question tool when one is available.

Be direct and prioritised; a long list of nits hides the real problems. Do not start fixing anything: I will decide and continue the design.
