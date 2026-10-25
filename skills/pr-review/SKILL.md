---
name: pr-review
description: "PR review step - explain a pull request (background, intuition, code), quiz the human on it, then record findings they can agree or disagree with"
disable-model-invocation: true
---

**Board language:** the first line of every `jarvis_read` answer says `Language: ...`. Write everything you put on the board in that language: titles and text of goals, tasks and widgets, and every `jarvis_comment`. Keep code, identifiers, and fixed names (widget kinds, steps, transitions, states) as they are. Do not translate existing content.
Argument: "[pull request URL or number, or Task N.M to continue]"
You are the reviewer of someone else's pull request. Input: the text the human typed after naming this workflow

## Tasks in Jarvis

Goals and tasks live in Jarvis, a live board I watch in the browser, never in files. Read with `jarvis_read`; create a PR review task with `jarvis_task_save` (`type: "pr_review"`); write every section with `jarvis_widgets` (call `jarvis_catalog` for the kinds). My comments arrive as "New comments from the human in Jarvis"; a message "Comments on widgets in Jarvis" is me pointing at one widget or part: change it, or answer in its thread with `jarvis_comment` `reply_to`. If a Jarvis tool reports that the server is unreachable, stop and tell me.

A PR review task moves: **Intake** → (`start explanation`, yours) → **Explanation** → (`quiz ready`, yours) → **Quiz** → (`findings ready`, yours) → **Findings** → (I give the verdict, or ask you to look again) → Done. After a verdict I can move it back with `re-review`, to Findings.

The aim is that I understand the change before I judge it. Write with clarity and flow, as a good essay does: each section leads into the next. Words sit next to the picture they explain; cut anything decorative. Do not write HTML files; everything is a widget.

## 1. Intake

Create the task if it does not exist, in the goal I name (or ask which). Write **pull request**: a `prose` widget with the link, the author's stated intent, and the size; a `callout` for anything risky. Then write the **existing discussion** in the same section: a `discussion` widget with every conversation comment, inline thread (file, line, resolved), and review verdict, read with `gh pr view --json comments,reviews` and `gh api graphql` (`reviewThreads` gives `isResolved`). If it cannot be read (gh missing, not signed in), write it with `status: "not_read"` and the failure; never write an empty discussion for a failed read. Read the diff (`gh pr view`, `gh pr diff`, or the branch), explore the code around it broadly, and read the project's instructions. Then `transition: "start explanation"`.

## 2. Explanation

Write three sections, in this order:

- **background**: the existing system the change touches. I may not know it, so start broad (`glossary_term` for terms, an `architecture` graph for how the parts relate), then narrow to what this change directly depends on. Say that the broad part can be skipped by someone who knows the system.
- **intuition**: the essence of the change, not the full details. A concrete toy example in `examples`, and a `diagram` of before and after (data flow with example data, or a simplified view of the UI for UI changes). Pick one or two diagram styles and reuse them. Use a `callout` for a key concept or an important edge case.
- **code**: a `walkthrough` of the change in the order that makes it understandable (not file order), each step a file, the line range, the excerpt, and what to notice. Add a `diagram` or `architecture` widget where the change reshapes how parts relate.

When I comment on a part, answer there or revise it. Then `transition: "quiz ready"`.

## 3. Quiz

Write **quiz**: a `quiz` widget in `feedback` mode with five questions of medium difficulty: you must understand the substance of the PR to answer, but none is a gotcha. Prefer predictions ("what happens if…") and choices with plausible wrong options. Each option has an explanation that teaches, right or wrong. You receive my answers; if they show a gap, revise the explanation widget they point at. Then `transition: "findings ready"` once I have answered, or when I ask to move on.

## 4. Findings

Write **findings**: a `findings` widget. Each finding has a severity (blocker, major, minor, nit), a path and line, an explanation that says why it matters, and a suggested change when you have one. Do not pad it: no nits that a formatter would catch. I mark each finding Agree, Disagree, or Fixed; when I comment on one, answer it or revise it, keeping the finding's id. The verdict is mine.

## 5. Re-review

When I say the author fixed things (the task is in Findings, or I moved it back with `re-review`), run a new round; earlier rounds and widgets stay as they are, so add widgets, never replace old ones.

- Read the pull request head (`gh pr view --json headRefOid`). If it equals the last round's (or the reviewed head from intake), write a `round` widget in **rounds** with `head` equal to `previous_head`, no commits, no statuses, and stop.
- Otherwise write a `round` widget (number, head, previous_head, the commits since, and for each finding of the previous round a status: `resolved` or `open` with the reason and the new `path:line`; `location_gone` with `old_location` when its file or line no longer exists, which you ask me about rather than resolve) and a fresh `discussion` widget in **rounds** with the discussion added since. I confirm or change each status; you never set my agree, disagree, or fixed marks.
- Review the changes since the previous round and add a new `findings` widget in **findings** for new issues (use ids that do not collide with earlier findings, e.g. `r2-f1`).

## 6. Comments for the author

Only when I ask you to draft review comments. Write **comments**: a `draft_comments` widget, separate from the findings (findings are for me, comments are public text for the author). Each draft has path, line (a line in the diff, on `side` RIGHT, or LEFT for removed lines), the diff `hunk` it attaches to copied from `gh pr diff` starting with its `@@` header, and the `body` exactly as it will be posted. Record `head` as the commit you drafted against; if the head moves before posting, set `current_head`. If a line is not in the diff the board flags the draft and I cannot approve it: re-anchor it.

Post only when I press Post: you receive a comment naming my verdict and the approved drafts. Then post **only** those drafts, as one review with that verdict, and nothing else, for example `gh api repos/OWNER/REPO/pulls/N/reviews --input -` with `{commit_id, event: APPROVE|REQUEST_CHANGES|COMMENT, comments: [{path, line, side, body}]}`. Never choose or default the verdict, and never post without approved drafts and a verdict. On success set `posted_url` on each posted draft (the comment's `html_url`; get them from the review's comments). On failure tell me what failed and change nothing: every draft stays approved and unposted. Replying in existing threads is out of scope.
