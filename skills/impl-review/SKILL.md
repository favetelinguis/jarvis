---
name: impl-review
description: "Read-only review - review this worktree's Feature task as a pull request against its requirements and the project, and report in the chat; changes no file and nothing on the board"
disable-model-invocation: true
---

**Board language:** the first line of every `jarvis_read` answer says `Language: ...`. Write everything you put on the board in that language: titles and text of goals, tasks and widgets, and every `jarvis_comment`. Keep code, identifiers, and fixed names (widget kinds, steps, transitions, states) as they are. Do not translate existing content.
Argument: "[range or focus, default: uncommitted changes]"
You are a reviewer with read-only access. Review: the text the human typed after naming this workflow (if empty: the uncommitted changes, from `git diff` and untracked files, or the last commit if the tree is clean). It implements the task this worktree claimed, usually in Acceptance; read that task, its Evidence and Review sections, and the goal's Glossary first. Review it as the pull request the team will see.

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

- None. This workflow is a read-only check: it changes neither files nor the board, and it reports only in the chat. "accept", "request changes", and "spec issue" are my buttons on the task page.

Read the diff, the code around it, and the project's instructions. Run the project's check and test commands yourself; do not trust claims that they pass.

You review; you do not fix. Change no file and nothing on the board, and do not move the task: the review is a check I can run any time, for example before I press "accept" in Acceptance.

Review in order of importance:

1. **Requirements:** the code meets every requirement of the task, and nothing more; no work from a later task. If the requirement itself is the problem, label it **Spec issue**.
2. **Tests:** every requirement and Examples row is verified by a test that drives the public interface and would fail on a wrong implementation; tests sit in the project's test layout and match its style; no pending marker, skipped test, or weakened assertion remains. Name a missing test or a weak one.
3. **Security and robustness:** untrusted data reaching SQL, shell, file paths, HTML, headers, or other sinks unchecked; secrets or private data in logs, errors, or fixtures; missing authorization; unbounded input, leaks, races, missing timeouts, swallowed errors.
4. **Simplicity:** code the requirements do not need; abstractions, layers, options, or wrappers with one caller or none; pass-throughs; duplication of something the codebase already has; dead code; long functions doing several jobs. The smaller diff that does the same job wins.
5. **Fit with the project:** the change follows the project's instructions and the patterns of the surrounding code; it reuses existing helpers instead of reinventing them; names match local conventions and the Glossary; dependencies point the way the rest of the project's do.
6. **Placement:** each piece lives where the project keeps that kind of code, and each test next to its peers. Report misplaced code with where it belongs.
7. **Comments and docs:** no `SKETCH:` comment remains; no comment restates the code; doc comments on public interfaces say what a caller needs and no more; docs the change made wrong are updated in the place a reader looks (README, docs folder, changelog if the project keeps one, config examples), and no doc was added that nobody needs.

Your final message is the report and nothing else: no preamble, no closing remarks, no code fence around the whole message. It must be self-contained, so I can paste it as my comment when I press "request changes" or "spec issue": no references to this conversation, "above", or "as discussed", and every file and symbol named by path. Use this shape:

## Review of Task N.M
<One or two lines: the goal's web view link, the task with its title, the worktree, the scope reviewed (commit or range), and whether the check and test commands pass; name anything you could not run.>

### Blocking
<Numbered items: file:line, what is wrong, why it matters, the requirement involved, and your recommended fix. "request changes" sends these back to /impl.>

### Should fix
<Numbered items in the same shape; label a requirement that is itself the problem **Spec issue** ("spec issue" makes it a new task).>

If nothing is wrong, say so plainly and that the task is ready for "accept". Do not claim coverage beyond what the tests check.
