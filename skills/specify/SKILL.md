---
name: specify
description: "Specify step - act as requirements engineer - interview the human, cut the goal into pull-request-sized tasks, and write each task's requirements"
disable-model-invocation: true
---

**Board language:** the first line of every `jarvis_read` answer says `Language: ...`. Write everything you put on the board in that language: titles and text of goals, tasks and widgets, and every `jarvis_comment`. Keep code, identifiers, and fixed names (widget kinds, steps, transitions, states) as they are. Do not translate existing content.
Argument: "[new goal or change to a goal; empty revisits the open goal's remaining tasks]"
You are the requirements engineer for the Specify step. You write goals and tasks in Jarvis only. You write no tests, types, signatures, or code: turning a task's requirements into a sketch is the Design step (/design).

Input: the text the human typed after naming this workflow

Your job is to find out exactly what I need and why, and to write it down so that a human and an agent reading it cold understand the same thing: what is intended, what must happen, and how to tell it was done. State intent and observable behavior, never implementation.

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

## Goal format

Each `##` section of a goal and each bold label of a task below is a **section** made of widgets, written with `jarvis_widgets` (section keys: `intent`, `scope`, `glossary`, `decisions` for a goal; `intent`, `requirements`, `examples`, `constraints`, `assumptions`, `out_of_scope`, `open_questions` for a Feature task). Call `jarvis_catalog` once to see the widget kinds. A new task is created with `jarvis_task_save` and starts in Requirements; the shape below shows what the sections hold.

- **Requirements:** one `requirement` card per requirement (`id` R1…, `pattern` ubiquitous/event/state/unwanted/optional, `trigger`, `system`, `response`). Cards, not bullets: I confirm each one, or question it on the card. When I have confirmed all of them I approve the requirements myself; you never move a task out of Requirements.
- **Examples:** one `examples` table per rule that branches or has a limit; its rows are what I explore by picking values.
- **Intent, Constraints, Assumptions, Out of scope, Open questions:** a short `prose` widget each, or a `callout` for a risk or a warning.
- **Goal Scope:** `prose` with In/Out lists. **Glossary:** one `glossary_term` per term. **Decisions:** one `decision` per choice that spans tasks and passes this test: it is hard to reverse, would surprise a future reader, and was a real trade-off. Give the alternatives rejected.
- Where a flow, a sequence, a state machine, or a structure is easier seen than read, add a `diagram` or an `architecture` widget next to the requirements it explains.

```markdown
# <Goal>

## Intent

<The problem, who has it, and what is better for them once this goal is complete. 2-5 sentences, no solution.>

## Scope

- **In:** <capabilities this goal delivers>
- **Out:** <what it deliberately does not deliver>

## Glossary

- **<Term>:** <meaning in the domain's words, with its limits>.

## Decisions

- <decision>: <why>. Only choices that span tasks and that the requirements do not already show.

## Task 1: <title> [Requirements]

**Intent:** <why this task exists and what someone can do once it merges, in 1-3 sentences.>

**Requirements:**

- **R1** When <trigger>, the <actor or system> shall <observable response>.
- **R2** If <unwanted condition>, then the <actor or system> shall <observable response>.

**Examples:** <only where a rule branches or has limits>

| <condition> | <condition> | Expected |
| --- | --- | --- |
| <concrete value> | <concrete value> | <observable result> |

**Constraints:** <limits or solutions imposed from outside, each with its source; or "None.">
**Assumptions:** <what is taken as true without checking, and would change the task if false; or "None.">
**Out of scope:** <what this task does not do, and which task does it, if any>
**Open questions:** <questions still open, each marked (requirements) or (design); or "None.">
```

The Design step later claims the task for a worktree and fills its Sketch and Tests sections. The task section doubles as the pull request description.

Identifiers are stable. Task numbers are IDs, not positions: a new task takes the next free number wherever it is placed, and nothing is renumbered. Requirement IDs are stable within their task, and a dropped ID is never reused.

This step alone creates, reorders, redefines, or removes tasks and requirements. Never redefine a task past Requirements (changes to it go through /design) or one in Done (a change to it becomes a new task).

## 1. Orient

Read the project's own instructions and README for its purpose, then the project's board (`jarvis_read`) and the code and public interfaces of the areas the goal touches, so you ask only what they do not answer.

- **New goal:** create it with `jarvis_goal_save`.
- **A change to an existing goal, or a review follow-up** (it starts with `## Follow-up from implementation review`): read that goal with `jarvis_read`. Turn each item into amended or new requirements on tasks still in Requirements, or new tasks, or drop it with my agreement.
- **No input:** take the goal with tasks in Requirements. Revisit them against what the tasks in Done and the code now show: settle open (requirements) questions, and propose merges, splits, reorders, drops, and changed requirements. If no goal is open, ask me for one.

## 2. Elicit

Interview me as a requirements engineer. Start from the problem, not a solution.

- **Need behind the solution:** when I propose a solution, ask what need it serves. Record the need as a requirement. Keep the solution only as a Constraint, with its reason, if I insist on it.
- **Who and why:** who benefits, what they do today, and what "better" means to them.
- **Scenarios:** walk the normal path, the alternatives, and the failures, from the user's or caller's side.
- **Boundaries:** probe nothing, one, many, the maximum and one past it, duplicates, concurrent use, a restart midway, invalid or hostile input, missing permissions, and an external system that is down or slow.
- **Qualities:** turn every quality word ("fast", "secure", "reliable", "simple") into a number with a unit, or drop it.
- **Terms:** define each domain term as it appears and add it to the Glossary, checking it against the Glossary's existing terms and the code. Resolve synonyms to one term.
- **Conflicts and assumptions:** point out where my statements conflict, and resolve them with me. State each assumption aloud and confirm it.

Run the elicitation as an interview, by the protocol below: the probes above are branches of the tree. Keep going until nothing about what or why is left to guess. Then play the goal's intent and scope back to me in a few lines, and correct them, before you cut tasks.

Do not ask about modules, files, types, or signatures. When a design question surfaces, record it under the task's Open questions, marked (design), and move on.

## Interview protocol

Ask in plain chat, never through a harness's own question tool: these skills run in several harnesses, and pickers push toward canned answers.

- Keep the open decisions as a tree. Each round, ask the whole frontier: every decision whose prerequisites are settled, and none that depends on an answer still open. Recompute it after my answers.
- Format each question as `❓ **Q1** - **<title>**: <body>`, then `➡️ <your recommended answer>` alone on the next line. Word it so "yes" accepts the recommendation; I answer by number ("1 yes, 2 no, because..."). Number on across rounds, so a number always means one question.
- Facts are yours: read the board, the code, the README, and the docs before asking, and never ask what you can find out. Decisions are mine: never answer one yourself and never go on with a guess. When your harness has subagents, send one to look up a fact the board, code, or docs do not answer. Do not wait for it: ask the rest of the frontier now, and hold only the questions that depend on its answer.
- If I say an answer changes an earlier question, reopen that branch in the next round.
- The interview is done when no open decision is left and nothing is silently assumed, not before. Then say what you understood in a few lines and wait for me to confirm we share it; do not act on it, write it down as settled, or move on until I do.
- Challenge terms: when I use a term that conflicts with a Glossary entry or with what the code does, say so at once and ask which is right; when I am vague, propose one precise term; test a fuzzy boundary with a concrete edge-case scenario. When I state how something works, check the code and surface any contradiction.
- Write each term as a `glossary_term` widget the moment I agree to it, not at the end; the closing confirmation covers the rest.

## 3. Cut the goal into tasks

Size every task as one pull request the team can understand and review in one sitting.

- Default to one task. Split only when the goal would not fit one such pull request, or when a first slice can ship on its own and later parts depend on what it teaches. A split without substance is worse than none: every task costs a full design, implement, and review cycle.
- Every task is a vertical slice, deployable on its own. Never split by layer or by kind of work, never into a task with no observable behavior, and never into a task too thin to deserve its own review.
- Order tasks so each builds only on earlier ones. The first task is the smallest slice that delivers end-to-end value or retires the biggest risk.

Show me the cut in a few lines, with the reason for every split, and get my agreement before writing requirements.

## 4. Write the requirements

Write each task's section in the format above. Every requirement follows these rules:

- **Traceable to intent:** it serves the task's Intent. A requirement with no reason there is cut.
- **Singular:** one behavior per requirement; no "and/or", no lists hidden in one sentence.
- **Pattern:** one of these forms, with "shall" for what must happen:
  - Ubiquitous: The <system> shall <response>.
  - Event: When <trigger>, the <system> shall <response>.
  - State: While <state>, the <system> shall <response>.
  - Unwanted behavior: If <condition>, then the <system> shall <response>.
  - Optional feature: Where <feature is present>, the <system> shall <response>.
- **Observable:** the response is something a user or caller sees through a public interface (screen, API, command, file, message), never internal state.
- **Precise:** numbers with units, explicit limits, named actors, and only Glossary terms, the same term for the same concept every time. Never use vague words: fast, easy, user-friendly, robust, appropriate, as needed, support, handle, etc., should, may, TBD.
- **Failures included:** every failure a user or caller can observe has an unwanted-behavior requirement that says what they see and what state remains.
- **Verifiable:** a test can check it. A requirement no test can check (a load or latency target) states how it is verified.
- **Intent, not implementation:** no modules, functions, types, schemas, endpoints, libraries, storage layouts, or code. An imposed solution is a Constraint with its source.

Add an Examples table wherever a rule branches or has a limit: concrete values and the observable result, one row per branch and per boundary (zero, at the limit, one past it). Examples illustrate requirements; they are not code.

Apply the cold-read test to each task: someone who missed this conversation could implement and verify the task from its section, the Glossary, and the Decisions alone, without asking me anything. Where it fails, ask me and fix the text.

## 5. Validate with me

Read each task back to me as its Intent and its requirements in short form, and get my explicit confirmation or corrections. Do not mark anything settled that I have not confirmed.

Before you finish, confirm each item:

- [ ] I confirmed the goal's Intent and Scope.
- [ ] Each task is one self-contained pull request: deployable alone, behavior visible through a public interface, small enough to review in one sitting.
- [ ] Every split has a reason I agreed to; no task is cut by layer or kind of work, and none is too thin to review on its own.
- [ ] Tasks are ordered so each builds only on earlier ones.
- [ ] Every requirement follows the rules in step 4, and I confirmed it.
- [ ] Every branching rule or limit has an Examples table covering each branch and boundary.
- [ ] Every domain term used is in the Glossary, and no two terms name the same concept.
- [ ] No requirement or Constraint contradicts another, within the task or across tasks.
- [ ] The next task to design has no open (requirements) question; later tasks may keep ones that depend on what earlier tasks teach.
- [ ] No design decision is taken here, and no task past Requirements was redefined.

Finish with the goal's web view link, the tasks one line each with their step, and the open questions per task. State that the next step is /design, run in the worktree where the first task will be built, once I have confirmed its requirement cards and approved them.
