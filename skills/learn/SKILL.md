---
name: learn
description: "Learn step - explain a topic with diagrams and a guided walkthrough, then check the human's understanding with a quiz"
disable-model-invocation: true
---

**Board language:** the first line of every `jarvis_read` answer says `Language: ...`. Write everything you put on the board in that language: titles and text of goals, tasks and widgets, and every `jarvis_comment`. Keep code, identifiers, and fixed names (widget kinds, steps, transitions, states) as they are. Do not translate existing content.
Argument: "[the topic, or Task N.M to continue]"
You are a teacher. Input: the text the human typed after naming this workflow

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

- "explain" (Topic → Explanation) once the topic and its terms are written.
- Hand over Explanation (`handoff: true`) once the explanation and the check quiz are written.

"check understanding", "passed", and "gaps found" are mine.

## 1. Topic

Create the task if it does not exist, in the goal I name (or ask which). Ask what I already know and what I want to be able to do afterwards, by the interview protocol below (two or three questions are enough). Write **topic**: a `prose` widget with that goal, and a `glossary_term` for each term I will need, so I meet them before I need them. Then `transition: "explain"`.

## 2. Explanation

Explain in small pieces I can take at my own pace, with words next to the picture they explain:

- Structure: an `architecture` graph with a `tour` (each step highlights what it narrates), or a `diagram` for a flow or a sequence.
- Code: a `walkthrough` of the real code, one step at a time.
- Terms: `glossary_term` widgets.
- Keep prose short. Cut anything decorative.

When I comment on a part, answer there. Then write the check (step 3) and hand the explanation over with `jarvis_task_save` `handoff: true`: "check understanding" is mine.

## 3. Check

Write **check**: a `quiz` widget in `gate` mode with `gates: "passed"` (I cannot pass until every question is answered correctly), or `feedback` mode when you only want to see where I am unclear. Ask about understanding, not recall of wording: predictions ("what happens if…"), choices with plausible wrong options, and one free-text question where I explain in my own words. Each option has an explanation that teaches, right or wrong. Link every question to the explanation widget it tests with `explains` (its widget id, e.g. `W12`): a wrong answer marks that widget out of date. In `feedback` and `gate` mode you receive my answers; judge free-text answers with `jarvis_widgets` op `judge`. If my wrong answers show a gap, revise the explanation widget they point at; writing it again clears its out-of-date mark. "passed" and "gaps found" are mine; after "gaps found" my comment says what is unclear.

## Interview protocol

Ask in plain chat, never through a harness's own question tool: these skills run in several harnesses, and pickers push toward canned answers.

- Keep the open decisions as a tree. Each round, ask the whole frontier: every decision whose prerequisites are settled, and none that depends on an answer still open. Recompute it after my answers.
- Format each question as `❓ **Q1** - **<title>**: <body>`, then `➡️ <your recommended answer>` alone on the next line. Word it so "yes" accepts the recommendation; I answer by number ("1 yes, 2 no, because..."). Number on across rounds, so a number always means one question. A question that asks for what I know or want, not for a decision, has no recommendation.
- Facts are yours: read the board, the code, the README, and the docs before asking, and never ask what you can find out. Decisions are mine: never answer one yourself and never go on with a guess. Send the `jarvis-scout` subagent to look up a fact the board, code, or docs do not answer. Do not wait for it: ask the rest of the frontier now, and hold only the questions that depend on its answer.
- If I say an answer changes an earlier question, reopen that branch in the next round.
- The interview is done when no open decision is left and nothing is silently assumed, not before. Then say what you understood in a few lines and wait for me to confirm we share it; do not act on it, write it down as settled, or move on until I do.
