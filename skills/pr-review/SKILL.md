---
name: pr-review
description: "PR review step - explain a pull request (background, intuition, code), quiz the human on it, then record findings they can agree or disagree with"
disable-model-invocation: true
---

**Board language:** the first line of every `jarvis_read` answer says `Language: ...`. Write everything you put on the board in that language: titles and text of goals, tasks and widgets, and every `jarvis_comment`. Keep code, identifiers, and fixed names (widget kinds, steps, transitions, states) as they are. Do not translate existing content.
Argument: "[pull request URL or number, or Task N.M to continue]"
You are the reviewer of someone else's pull request. Input: the text the human typed after naming this workflow

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

- "start explanation" (Intake → Explanation) once the pull request and its discussion are written.
- Hand over Explanation (`handoff: true`) once background, intuition, code, and the quiz are written.
- "findings ready" (Quiz → Findings) once the findings are written. The board refuses it until I answered every quiz question or pressed Skip quiz.

"ready for the quiz", "give verdict", "look again", and "re-review" are mine.

The aim is that I understand the change before I judge it. Write with clarity and flow, as a good essay does: each section leads into the next. Words sit next to the picture they explain; cut anything decorative. Do not write HTML files; everything is a widget.

## 1. Intake

Create the task if it does not exist, in the goal I name (or ask which). Write **pull request**: a `prose` widget with the link, the author's stated intent, and the size; a `callout` for anything risky. Then write the **existing discussion** in the same section: a `discussion` widget with every conversation comment, inline thread (file, line, resolved), and review verdict, read with `gh pr view --json comments,reviews` and `gh api graphql` (`reviewThreads` gives `isResolved`). If it cannot be read (gh missing, not signed in), write it with `status: "not_read"` and the failure; never write an empty discussion for a failed read. Read the diff (`gh pr view`, `gh pr diff`, or the branch), explore the code around it broadly, and read the project's instructions. Then `transition: "start explanation"`.

## 2. Explanation

Write three sections, in this order:

- **background**: the existing system the change touches. I may not know it, so start broad (`glossary_term` for terms, an `architecture` graph for how the parts relate), then narrow to what this change directly depends on. Say that the broad part can be skipped by someone who knows the system.
- **intuition**: the essence of the change, not the full details. A concrete toy example in `examples`, and a `diagram` of before and after (data flow with example data, or a simplified view of the UI for UI changes). Pick one or two diagram styles and reuse them. Use a `callout` for a key concept or an important edge case.
- **code**: a `walkthrough` of the change in the order that makes it understandable (not file order), each step a file, the line range, the excerpt, and what to notice. Add a `diagram` or `architecture` widget where the change reshapes how parts relate.

When I comment on a part, answer there or revise it. Then write the quiz (step 3) and hand the explanation over with `jarvis_task_save` `handoff: true`: "ready for the quiz" is mine.

## 3. Quiz

Write **quiz**: a `quiz` widget in `feedback` mode with five questions of medium difficulty: you must understand the substance of the PR to answer, but none is a gotcha. Prefer predictions ("what happens if…") and choices with plausible wrong options. Each option has an explanation that teaches, right or wrong. Write it while the task is in Explanation. You receive my answers; if they show a gap, revise the explanation widget they point at. Once I have answered every question, or pressed Skip quiz, the turn is yours: write the findings (step 4), then `transition: "findings ready"`.

## 4. Findings

Write **findings**: a `findings` widget. Each finding has a severity (blocker, major, minor, nit), a path and line, an explanation that says why it matters, and a suggested change when you have one. Do not pad it: no nits that a formatter would catch. I mark each finding Agree, Disagree, or Fixed; when I comment on one, answer it or revise it, keeping the finding's id. The verdict is mine.

Before I see the first round's findings I write my own view: my concerns, one per line, ids `c1`, `c2`, …. It arrives as a message from the board; a changed view arrives again. Compare it with your findings and write one `view_matches` widget in **picture**: one match per finding of the first round, with the concern it covers, or no concern. Never change my concerns, and keep my own matches: the board shows mine over yours.

## 5. Re-review

When I say the author fixed things (the task is in Findings, or I moved it back with `re-review`), run a new round; earlier rounds and widgets stay as they are, so add widgets, never replace old ones.

- Read the pull request head (`gh pr view --json headRefOid`). If it equals the last round's (or the reviewed head from intake), write a `round` widget in **rounds** with `head` equal to `previous_head`, no commits, no statuses, and stop.
- Otherwise write a `round` widget (number, head, previous_head, the commits since, and for each finding of the previous round a status: `resolved` or `open` with the reason and the new `path:line`; `location_gone` with `old_location` when its file or line no longer exists, which you ask me about rather than resolve) and a fresh `discussion` widget in **rounds** with the discussion added since. I confirm or change each status; you never set my agree, disagree, or fixed marks.
- A round with a new head marks the quiz and the earlier findings out of date. Review the changes since the previous round and add a new `findings` widget in **rounds** for new issues (use ids that do not collide with earlier findings, e.g. `r2-f1`).

## 6. Comments for the author

Only when I ask you to draft review comments. Write **comments**: a `draft_comments` widget, separate from the findings (findings are for me, comments are public text for the author). Each draft has path, line (a line in the diff, on `side` RIGHT, or LEFT for removed lines), the diff `hunk` it attaches to copied from `gh pr diff` starting with its `@@` header, and the `body` exactly as it will be posted. Record `head` as the commit you drafted against; if the head moves before posting, set `current_head`. If a line is not in the diff the board flags the draft and I cannot approve it: re-anchor it.

Post only when I press Post: you receive a comment naming my verdict and the approved drafts. Then post **only** those drafts, as one review with that verdict, and nothing else, for example `gh api repos/OWNER/REPO/pulls/N/reviews --input -` with `{commit_id, event: APPROVE|REQUEST_CHANGES|COMMENT, comments: [{path, line, side, body}]}`. Never choose or default the verdict, and never post without approved drafts and a verdict. On success set `posted_url` on each posted draft (the comment's `html_url`; get them from the review's comments). On failure tell me what failed and change nothing: every draft stays approved and unposted. Replying in existing threads is out of scope.
