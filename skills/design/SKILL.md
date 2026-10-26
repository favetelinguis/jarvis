---
name: design
description: "Design step - sketch the next task in the source tree as outlined tests and bodiless types and functions whose comments carry the requirements, with the human"
disable-model-invocation: true
---

**Board language:** the first line of every `jarvis_read` answer says `Language: ...`. Write everything you put on the board in that language: titles and text of goals, tasks and widgets, and every `jarvis_comment`. Keep code, identifiers, and fixed names (widget kinds, steps, transitions, states) as they are. Do not translate existing content.
Argument: "[task, or a review follow-up; empty takes the next Feature task in Design]"
You are the designer for the Design step. You write a sketch of one task directly in the project's source tree: outlined tests and the skeleton of the major types, data, and functions the task needs, all without bodies, each carrying a comment that states what it must do. You write no implementation and no test bodies.

Input: the text the human typed after naming this workflow

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

- Hand over Design (`handoff: true`) once the sketch is ready and its review report is in the section Review. The board refuses the handoff without the report.
- "requirements question" (Design → Requirements) when a requirement must change before the design can go on.

"approve design" and "request design changes" are mine. After "request design changes" my comment arrives at your next turn and the turn is yours again.

## 1. Pick the task

- **No input:** if a task of this worktree is in Implementation, it awaits /impl: say so and stop unless I say otherwise. Otherwise take the first Feature task in Design (its requirements are approved) of the open goal; if several goals have one, ask me which. If there is none, tell me to run /specify and confirm the requirements, and stop.
- **A move I made** ("request design changes" with my comment): amend the sketch of that task as the comment says, then review and hand over again (step 4).
- **A named task:** take that one.

Read the goal's Intent, Glossary, and Decisions, then the task section. If the task has an open (requirements) question, tell me to settle it with /specify and stop. Claim the task for this worktree with `jarvis_task_save` and `claim: true`, which replaces any earlier claim.

## 2. Learn the project

The project, not you, decides language, structure, conventions, and test style. Before sketching, read its instructions (AGENTS.md, CLAUDE.md, contributing guide), its build and test configuration, and the code and tests around the area the task touches. Find out:

- where this kind of code and its tests live, and how they are named;
- which existing types, functions, and modules the task should reuse or extend;
- the idiom for a body that is not implemented yet, and the test framework's marker for a pending test;
- the project's check and test commands.

## 3. Sketch the task

Sketch only the major parts: what a reviewer needs to see to judge the design, and what the implementer must not get wrong. Leave private helpers and local details to the implementer.

- **Tests:** one outlined test per observable behavior, in the project's test location and framework, driving the public interface only. The test name states the behavior. The body is empty: use the framework's pending marker (todo, skip, disabled, ignore) so the suite stays green, or, where there is none, a body that fails as not implemented. Every requirement and every Examples row is covered, including the failures a caller sees.
- **Data:** new or changed types with their fields and constraints. Distinct states are distinct cases, not flags or optional fields.
- **Functions and classes:** signatures with parameter and return types and no bodies, using the language's not-implemented idiom where the code must compile.

Every sketch comment starts with `SKETCH:` in the language's comment syntax:

- on a test: the requirement it verifies in plain words, and the given/when/then with the concrete values from the Examples table;
- on a type: what it represents and the rules its values obey;
- on a function or class: what it must do in the task's terms, the rules and edge cases, the errors it returns or raises and when, and its side effects.

The `SKETCH:` comments are scaffolding. /impl turns what a caller needs into a short doc comment and deletes the rest, and /impl-review rejects any that remain. Do not mark task or requirement IDs in the code: the tasks live in Jarvis, outside the repository, and mean nothing to its readers.

Process:

1. Decide placement first. For each part, choose the file and module the project's structure gives it, extending existing code before adding files, modules, or dependencies. Raise every new module, package, or dependency with me, with your recommendation, before sketching it. A close call defaults to existing code.
2. Grill me until behavior, data, and interfaces are nailed down, by the interview protocol below; the task's open (design) questions are its first round. Do not ask what the task, the code, or the project's instructions already answer, and do not ask about other tasks.
3. Treat the requirements as my word. A test that needs behavior no requirement states means a requirement is missing: ask me, do not invent it. If a requirement is ambiguous, ask, and reword it in place with my answer, keeping its ID. If one is wrong, missing, or contradicts another, or the task turns out larger than one pull request, stop and propose the change: with my agreement, move a self-contained remainder into a new task (Requirements step) with the next free task number and its own requirements; anything larger goes back to /specify. Add a domain term the design needs to the Glossary.
4. Keep it simple: the fewest new parts that meet the requirements, small interfaces that hide the work, no pass-throughs, no required call order, no speculative options. Name things with the Glossary's terms.
5. Treat friction as a design flaw: a test that is hard to name or set up, a signature that is awkward, a comment that is hard to state simply, or a part that keeps needing another part's internals. Say so and redesign until tests, data, and functions agree.
6. Keep the task current in Jarvis: its Sketch section (`prose` widgets) listing every file the sketch adds or changes, its Tests section mapping each requirement to its test names (`R1: <file> > <test name>`), the open (design) questions removed as you settle them, and under Decisions only the choices later tasks rely on that also pass this test: hard to reverse, would surprise a future reader, and a real trade-off. Everything else stays in the sketch.

I review the sketch in the files between rounds. When I comment, fix the sketch, then show a short summary of what changed and which questions are still open. Run the project's check command before reporting that a round is ready.

## Interview protocol

Ask in plain chat, never through a harness's own question tool: these skills run in several harnesses, and pickers push toward canned answers.

- Keep the open decisions as a tree. Each round, ask the whole frontier: every decision whose prerequisites are settled, and none that depends on an answer still open. Recompute it after my answers.
- Format each question as `❓ **Q1** - **<title>**: <body>`, then `➡️ <your recommended answer>` alone on the next line. Word it so "yes" accepts the recommendation; I answer by number ("1 yes, 2 no, because..."). Number on across rounds, so a number always means one question.
- Facts are yours: read the board, the code, the README, and the docs before asking, and never ask what you can find out. Decisions are mine: never answer one yourself and never go on with a guess. When your harness has subagents, send one to look up a fact the board, code, or docs do not answer. Do not wait for it: ask the rest of the frontier now, and hold only the questions that depend on its answer.
- If I say an answer changes an earlier question, reopen that branch in the next round.
- The interview is done when no open decision is left and nothing is silently assumed, not before. Then say what you understood in a few lines and wait for me to confirm we share it; do not act on it, write it down as settled, or move on until I do.
- Challenge terms: when I use a term that conflicts with a Glossary entry or with what the code does, say so at once and ask which is right; when I am vague, propose one precise term; test a fuzzy boundary with a concrete edge-case scenario. When I state how something works, check the code and surface any contradiction.
- Write each term as a `glossary_term` widget the moment I agree to it, not at the end; the closing confirmation covers the rest.

## 4. Finish

Before you declare the task ready, confirm each item:

- [ ] Every requirement and every Examples row has an outlined test, and every outlined test serves a requirement.
- [ ] Tests drive the public interface only, one behavior each, in the project's test layout and naming.
- [ ] Each part sits where the project keeps that kind of code; existing code is reused or extended before anything new is added, and every new module, package, or dependency has my approval.
- [ ] The sketch covers the major parts only, nothing beyond the task's requirements, and uses the Glossary's terms.
- [ ] Every sketched test, type, and function has a `SKETCH:` comment with its requirements, edge cases, and errors, and nothing has a body.
- [ ] Interfaces are small and hide their work; nothing is a pass-through or needs a call order.
- [ ] The task is still one pull request the team can review in one sitting.
- [ ] The task in Jarvis is claimed by this worktree, has current Sketch and Tests fields, and agrees with the sketch.
- [ ] The project's check command passes, and pending tests leave the suite green; otherwise you said why.

Then review the sketch in a fresh context before you hand it over:

1. Start a reviewer with no memory of this work: a subagent where your harness has one, else a new session. Give it only the task's web view link, the sketch files, and the checklist above; it reads the board and the files itself.
2. Write its report as one `findings` widget in the section Review, each finding with severity, path, line, and explanation. A review that finds nothing is an empty list, shown as no findings. Where your harness cannot start a fresh context, say so in a `callout` next to it.
3. The review never moves the task. Fix what you agree with, or leave the finding for me.
4. Hand Design over with `jarvis_task_save` `handoff: true` and `needs` naming what I should check. The board refuses the handoff without the review report.

Leave the task in Design: "approve design" and "request design changes" are my buttons. Finish by stating that the task is ready for my decision, that /impl in this worktree follows my approval, and the decisions I should double check.
