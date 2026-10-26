---
name: design-review
description: "Design checkpoint inside a design session - check the task's sketch against its requirements, the project's structure, and simplicity, then refocus"
disable-model-invocation: true
---

**Board language:** the first line of every `jarvis_read` answer says `Language: ...`. Write everything you put on the board in that language: titles and text of goals, tasks and widgets, and every `jarvis_comment`. Keep code, identifiers, and fixed names (widget kinds, steps, transitions, states) as they are. Do not translate existing content.
Argument: "[what you are worried about]"
Checkpoint for the design session we are in. Focus: the text the human typed after naming this workflow (if empty: the whole sketch of the task being designed).

Read-only: do not modify files. Use the goal's Intent and Glossary, the task's requirements, and this conversation as the record of my intent. Read the task with `jarvis_read`, then the sketch files in its Sketch section, and find every `SKETCH:` comment; use `git status` and `git diff` to see what changed this session. Run the project's check command.

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

- None. This workflow is a read-only check: it changes neither files nor the board, and it reports only in the chat. "approve design" and "request design changes" are my buttons on the task page.

Report briefly, skipping any section with nothing to say except implementation blockers, which you always report:

1. **Intent:** restate in a few lines what this task is for. Then say where the sketch has drifted from the requirements or this conversation, or grown beyond them. Call out places where I changed my mind and older parts of the sketch or the task section were not updated.
2. **Coverage and scope:** requirements or Examples rows with no outlined test; outlined tests that serve no requirement; behavior the sketch adds that no requirement states (a missing requirement to take back to me); a Tests or Sketch field in Jarvis that does not match the files; names that stray from the Glossary; a task that has grown past one pull request (name the self-contained part to move into a new task, or say it needs /specify).
3. **Implementation blockers:** anything the implementer could not resolve alone: requirements or `SKETCH:` comments that contradict each other; a test that can only be checked through internals; a sketched part with no place in the project's structure; a needed dependency or module I have not approved; the check command failing. Name the files and the decision needed. If there are none, say "No implementation blockers found."
4. **Fit with the project:** parts placed where the project does not keep that kind of code; new files, modules, helpers, or dependencies where existing ones would do; tests outside the project's test layout or style; conventions in the project's instructions the sketch breaks.
5. **Simplicity:** parts the requirements do not need, shallow wrappers and pass-throughs, interfaces that leak decisions or need a call order, errors pushed onto callers, states as flags, and anything hard to describe in one sentence. Suggest the simpler shape.
6. **Sketch quality:** bodies that were written; major parts with no `SKETCH:` comment; comments too vague to implement from, or that omit an edge case or error the requirements name; detail that belongs to the implementer.
7. **Next:** what to resolve before this task is ready, implementation blockers first, as concrete questions or edits. Put the ones that need my decision to me by the interview protocol below, until none is open.

Be direct and prioritised; a long list of nits hides the real problems. Do not start fixing anything: I will decide and continue the design. Leave the board and the task's step as they are, and report only here in the chat: approving the design is my button on the task page.

## Interview protocol

Ask in plain chat, never through a harness's own question tool: these skills run in several harnesses, and pickers push toward canned answers.

- Keep the open decisions as a tree. Each round, ask the whole frontier: every decision whose prerequisites are settled, and none that depends on an answer still open. Recompute it after my answers.
- Format each question as `❓ **Q1** - **<title>**: <body>`, then `➡️ <your recommended answer>` alone on the next line. Word it so "yes" accepts the recommendation; I answer by number ("1 yes, 2 no, because..."). Number on across rounds, so a number always means one question.
- Facts are yours: read the board, the code, the README, and the docs before asking, and never ask what you can find out. Decisions are mine: never answer one yourself and never go on with a guess. When your harness has subagents, send one to look up a fact the board, code, or docs do not answer. Do not wait for it: ask the rest of the frontier now, and hold only the questions that depend on its answer.
- If I say an answer changes an earlier question, reopen that branch in the next round.
- The interview is done when no open decision is left and nothing is silently assumed, not before. Then say what you understood in a few lines and wait for me to confirm we share it; do not act on it, write it down as settled, or move on until I do.
