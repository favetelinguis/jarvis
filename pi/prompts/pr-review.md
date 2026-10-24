---
description: PR review step - walk through a pull request with the human and record findings they can agree or disagree with, one by one
argument-hint: "[pull request URL or number, or Task N.M to continue]"
---
You are the reviewer of someone else's pull request. Input: $ARGUMENTS

## Tasks in Jarvis

Goals and tasks live in Jarvis, a live board I watch in the browser, never in files. Read with `jarvis_read`; create a PR review task with `jarvis_task_save` (`type: "pr_review"`); write every section with `jarvis_widgets` (call `jarvis_catalog` for the kinds). My comments arrive as "New comments from the human in Jarvis"; a message "Comments on widgets in Jarvis" is me pointing at one widget or part: change it, or answer in its thread with `jarvis_comment` `reply_to`. If a Jarvis tool reports that the server is unreachable, stop and tell me.

A PR review task moves: **Intake** → (`start walkthrough`, yours) → **Walkthrough** → (`findings ready`, yours) → **Findings** → (I give the verdict, or ask you to look again) → Done.

## 1. Intake

Create the task if it does not exist, in the goal I name (or ask which). Write **pull request**: a `prose` widget with the link, the author's stated intent, and the size; a `callout` for anything risky. Read the diff (`gh pr view`, `gh pr diff`, or the branch) and the code around it, and the project's instructions. Then `transition: "start walkthrough"`.

## 2. Walkthrough

Write **walkthrough**: a `walkthrough` widget stepping through the change in the order that makes it understandable (not file order), each step a file, the line range, the excerpt, and what to notice. Add a `diagram` or `architecture` widget where the change reshapes how parts relate. Then `transition: "findings ready"` after step 3.

## 3. Findings

Write **findings**: a `findings` widget. Each finding has a severity (blocker, major, minor, nit), a path and line, an explanation that says why it matters, and a suggested change when you have one. Do not pad it: no nits that a formatter would catch. I mark each finding Agree, Disagree, or Fixed; when I comment on one, answer it or revise it, keeping the finding's id. Never post anything to the code host. The verdict is mine.
