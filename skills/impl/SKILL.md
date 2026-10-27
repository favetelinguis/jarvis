---
name: impl
description: "Implement step - make this worktree's task in Implementation work, starting from its sketch, as well as you can"
disable-model-invocation: true
---

**Board language:** the first line of every `jarvis_read` answer says `Language: ...`. Write everything you put on the board in that language: titles and text of goals, tasks and widgets, and every `jarvis_comment`. Keep code, identifiers, and fixed names (widget kinds, steps, transitions, states) as they are. Do not translate existing content.
Argument: "[task, default: the task of this worktree in Implementation]"
You are the implementer for the Implement step. Scope: the text the human typed after naming this workflow (if empty: the task of this worktree in Implementation; if there is none, or more than one, stop and ask me which).

## Tasks in Jarvis

Goals and tasks live in Jarvis, a live board I watch in the browser. `jarvis_read` with no arguments shows this project's board; with `goal` a whole goal; with `goal` and `task` a whole task: its type, its step, whose turn it is, the sections you may write, the transitions out of it, every widget with its widget id and part ids, and its comments. All worktrees of a repository share one board. Goals are numbered per project and tasks per goal; refer to them as Goal N and Task N.M.

<!-- board-rules -->
### Board rules

The same rules hold in every Jarvis workflow. The board enforces what it can; you keep the rest.

1. MUST keep goals and tasks in Jarvis, never in files: read with `jarvis_read`, write with `jarvis_goal_save`, `jarvis_task_save`, `jarvis_widgets`, and `jarvis_comment`.
2. MUST write every section as widgets from `jarvis_catalog`, preferring visual ones over prose, and keep the ids of list items when you update a widget, so my comments, answers, and confirmations stay attached.
3. MUST write in a task only the sections its current step owns; `jarvis_read` lists them for the step.
4. MUST NOT make a transition whose mover is the human, even when I ask for it in the chat: tell me which button to press on the task page.
5. MUST make the transitions this workflow owns, listed below, the moment they hold, and no others.
6. MUST hand a step over with `jarvis_task_save` `handoff: true` when your work in a step that is handed over is ready for my decision.
7. MUST give `reason` in one line on every `jarvis_widgets` and `jarvis_task_save` call; when the change records my answer to question Qn, start it with the number, e.g. `Q3 → R2 reworded`.
8. MUST give `needs` in one line when I must do something before you can go on.
9. MUST treat what arrives from the board at the start of a turn as my word: "Moves and messages from the human in Jarvis" (a move I made, with my comment), "New comments from the human in Jarvis", and "Comments on widgets in Jarvis" (change that widget, or answer it with `jarvis_comment` `reply_to` if it is only a question).
10. MUST write a widget marked Out of date again before you rely on it; writing it again clears the mark.
11. MUST NOT use `force_step`; only /poc uses it, and only in a goal marked POC.
12. MUST work on a Feature task past Requirements only from the worktree that claimed it (`claim: true`).
13. MUST stop and tell me when a Jarvis tool reports that the server is unreachable; never fall back to files.
<!-- /board-rules -->

### Transitions this workflow owns

- "implemented" (Implementation → Acceptance) once the evidence and the review report are on the board. The board refuses it while evidence or the review is missing or out of date, the check failed, or a requirement lacks a passing test.

"accept", "request changes", and "spec issue" are mine.

Work autonomously and solve the problem as well as you can. Ask me only when a requirement is contradictory or impossible to meet; then stop, explain the problem and the options, and hand it back.

1. **Read.** The goal's Glossary and Decisions, the task section, then the files in its Sketch field and every `SKETCH:` comment in them. Read the project's instructions and the code around the sketch, so the result looks like the rest of the codebase.
2. **Tests first.** Write the bodies of the outlined tests and remove their pending markers. Run them and see them fail for the right reason.
3. **Implement** until they pass, following the project's conventions. The sketch is the starting design, not a contract: when the code shows a simpler or better-fitting signature, type, or placement, change it and say so in your report. The requirements are fixed.
4. **More tests where they earn their place:** an edge case the outline missed, or a bug you hit on the way, pinned at the level the project already tests.
5. **Clean up comments.** Delete every `SKETCH:` comment. Keep only what a reader cannot get from the code: a short doc comment where a caller needs to know something (in the project's doc style), and a why comment where a decision is not obvious. Most sketched functions end with no comment at all.
6. **Docs:** update existing docs only where this change made them wrong or a user or caller will look for it. Add no new doc files.
7. **Verify:** run the project's check and test commands until they pass. Confirm no `SKETCH:` comment and no pending marker from the outline remains.
8. **Review in a fresh context, in a loop:**
   1. Start the `jarvis-impl-reviewer` subagent, which has no memory of this work, on the diff and the task's web view link, with the open items already with me. It reports findings, each with an owner (`[agent]` or `[human]`); it fixes nothing.
   2. A `Critical` section: stop the loop. Fix nothing else, not even the trivial findings, because the change may be redone. Write the report and tell me; do not move the task.
   3. Otherwise fix every `[agent]` finding, whatever its severity, then run the project's check and test commands until they pass. Keep every `[human]` finding (every Spec issue included) open for me; do not guess at it.
   4. Start a fresh `jarvis-impl-reviewer` (a new subagent, never the same one) on the fixed change and repeat from 2. Stop when it reports nothing, when only `[human]` findings are left, when a `Critical` section appears, or after five rounds or when a round brings back a finding you already fixed (say so).
   5. Write the last report as one `findings` widget in the section Review, with what is left. A review that finds nothing is an empty list. Where the subagent cannot start, say so in a `callout` next to it.
9. **Evidence:** write one `evidence` widget in the section Evidence: the check command, its result, a short excerpt of its output, and one row per requirement card with its test (`file > test name`) and whether it passed. Every row names a requirement card of the task. Record what you ran; never a result you did not see.

Implement this task only: work that belongs to a later task stays out, even when it is easy. In Jarvis, change only the task's Sketch, Tests, Review, and Evidence sections, and only to match what you actually built; when the work is done, move the task with `jarvis_task_save` `transition: "implemented"`. The board refuses it while evidence or the review is missing or out of date, the check failed, or a requirement lacks a passing test: fix what it names.

Your report is short and contains only:

1. Where you departed from the sketch, and why, one line each.
2. Tests you added beyond the outline, one line each.
3. Anything you could not run, instead of claiming it passed.
4. Findings left open for me, and how many review rounds ran.

Do not summarize the implementation or the test output. Omit any item with nothing to say; if all are empty, say "Done."
