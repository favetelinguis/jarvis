---
description: Implement step - make this worktree's ready task work, starting from its sketch, as well as you can
argument-hint: "[task, default: the [ready] task of this worktree]"
---
You are the implementer for the Implement step. Scope: $ARGUMENTS (if empty: the `[ready]` task of this worktree; if there is none, or more than one, stop and ask me which).

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

Work autonomously and solve the problem as well as you can. Ask me only when a requirement is contradictory or impossible to meet; then stop, explain the problem and the options, and hand it back.

1. **Read.** The goal's Glossary and Decisions, the task section, then the files in its Sketch field and every `SKETCH:` comment in them. Read the project's instructions and the code around the sketch, so the result looks like the rest of the codebase.
2. **Tests first.** Write the bodies of the outlined tests and remove their pending markers. Run them and see them fail for the right reason.
3. **Implement** until they pass, following the project's conventions. The sketch is the starting design, not a contract: when the code shows a simpler or better-fitting signature, type, or placement, change it and say so in your report. The requirements are fixed.
4. **More tests where they earn their place:** an edge case the outline missed, or a bug you hit on the way, pinned at the level the project already tests.
5. **Clean up comments.** Delete every `SKETCH:` comment. Keep only what a reader cannot get from the code: a short doc comment where a caller needs to know something (in the project's doc style), and a why comment where a decision is not obvious. Most sketched functions end with no comment at all.
6. **Docs:** update existing docs only where this change made them wrong or a user or caller will look for it. Add no new doc files.
7. **Verify:** run the project's check and test commands until they pass. Confirm no `SKETCH:` comment and no pending marker from the outline remains.

Implement this task only: work that belongs to a later task stays out, even when it is easy. In Jarvis, change only the task's Sketch and Tests fields, and only to match what you actually built.

Your report is short and contains only:

1. Where you departed from the sketch, and why, one line each.
2. Tests you added beyond the outline, one line each.
3. Anything you could not run, instead of claiming it passed.
4. Concerns the reviewer should look at.

Do not summarize the implementation or the test output. Omit any item with nothing to say; if all are empty, say "Done."
