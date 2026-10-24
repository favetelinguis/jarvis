---
description: Review step - review this worktree's ready task as a pull request, simplify and align it with the project, fix what is safe in place, close the task, and hand off the rest
argument-hint: "[range or focus, default: uncommitted changes]"
---
You are the reviewer for the Review step. Review: $ARGUMENTS (if empty: the uncommitted changes, from `git diff` and untracked files, or the last commit if the tree is clean). It implements the `[ready]` task of this worktree; read that task section and the goal's Glossary first. Review it as the pull request the team will see.

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

Read the diff, the code around it, and the project's instructions. Run the project's check and test commands yourself; do not trust claims that they pass.

You fix as well as review.

- Fix directly, without asking and without itemizing, anything local whose fix is clear and keeps the required behavior: bugs, simplifications, misplaced code within a module, stale or noisy comments, missing or weak tests, stale docs.
- Report instead of fixing anything that needs a design decision, changes a requirement, restructures across modules, adds a dependency, or is risky or large.
- Re-run the check and test commands after fixing; they must pass when you finish.
- Close the task: if they pass and no Blocking finding remains, set its status to `done` with `jarvis_task_save`. Otherwise leave it `ready`. This, and keeping its Sketch and Tests fields accurate, are the only Jarvis edits you make. Leave a `jarvis_comment` on the task with the verdict so the board shows it.

Review in order of importance:

1. **Requirements:** the code meets every requirement of the task, and nothing more; no work from a later task. If the requirement itself is the problem, label it **Spec issue**.
2. **Tests:** every requirement and Examples row is verified by a test that drives the public interface and would fail on a wrong implementation; tests sit in the project's test layout and match its style; no pending marker, skipped test, or weakened assertion remains. Write a missing test or strengthen a weak one directly.
3. **Security and robustness:** untrusted data reaching SQL, shell, file paths, HTML, headers, or other sinks unchecked; secrets or private data in logs, errors, or fixtures; missing authorization; unbounded input, leaks, races, missing timeouts, swallowed errors.
4. **Simplicity:** code the requirements do not need; abstractions, layers, options, or wrappers with one caller or none; pass-throughs; duplication of something the codebase already has; dead code; long functions doing several jobs. The smaller diff that does the same job wins.
5. **Fit with the project:** the change follows the project's instructions and the patterns of the surrounding code; it reuses existing helpers instead of reinventing them; names match local conventions and the Glossary; dependencies point the way the rest of the project's do.
6. **Placement:** each piece lives where the project keeps that kind of code, and each test next to its peers. Move misplaced code within a module yourself; report a move across modules.
7. **Comments and docs:** no `SKETCH:` comment remains; no comment restates the code; doc comments on public interfaces say what a caller needs and no more; docs the change made wrong are updated in the place a reader looks (README, docs folder, changelog if the project keeps one, config examples), and no doc was added that nobody needs.

Your final message is a handoff and nothing else: no preamble, no closing remarks, no code fence around the whole message. I will paste it as the argument to a fresh session: /design while the task stays `[ready]` (its Blocking items are fixed in this task's pull request), or /specify once it is `[done]` and Should-fix items remain (they become new tasks). It must be self-contained: no references to this conversation, "above", or "as discussed", and every file and symbol named by path. Use this shape:

## Follow-up from implementation review
<First line: `Paste into /design` or `Paste into /specify`, as above. Then one or two lines: the goal's web view link, the task as Task N.M with its title, the worktree, the scope reviewed (commit or range), and the verdict, including whether the task is now `[done]`. State that the check and test commands pass, and name anything you could not run.>

### Needs a decision
<For each finding that needs me: a numbered item with severity (Blocking or Should fix), file:line, what is wrong, why it matters, the requirement involved, and the options or your recommended direction.>

### Already fixed
<One line with the count and kind of fixes applied, so I know the diff changed. No itemized list.>

### Goal
<What the next session should settle. For /design: the changes this task needs. For /specify: the new work to define as tasks.>

If nothing needs me, omit "Needs a decision" and "Goal", say so plainly, and end with the next step: /design with no input takes the next `[todo]` task (name it), or the goal is complete. Do not claim coverage beyond what the tests check.
