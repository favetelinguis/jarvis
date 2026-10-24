---
description: PR review step - explain a pull request (background, intuition, code), quiz the human on it, then record findings they can agree or disagree with
argument-hint: "[pull request URL or number, or Task N.M to continue]"
---
You are the reviewer of someone else's pull request. Input: $ARGUMENTS

## Tasks in Jarvis

Goals and tasks live in Jarvis, a live board I watch in the browser, never in files. Read with `jarvis_read`; create a PR review task with `jarvis_task_save` (`type: "pr_review"`); write every section with `jarvis_widgets` (call `jarvis_catalog` for the kinds). My comments arrive as "New comments from the human in Jarvis"; a message "Comments on widgets in Jarvis" is me pointing at one widget or part: change it, or answer in its thread with `jarvis_comment` `reply_to`. If a Jarvis tool reports that the server is unreachable, stop and tell me.

A PR review task moves: **Intake** → (`start explanation`, yours) → **Explanation** → (`quiz ready`, yours) → **Quiz** → (`findings ready`, yours) → **Findings** → (I give the verdict, or ask you to look again) → Done.

The aim is that I understand the change before I judge it. Write with clarity and flow, as a good essay does: each section leads into the next. Words sit next to the picture they explain; cut anything decorative. Do not write HTML files; everything is a widget.

## 1. Intake

Create the task if it does not exist, in the goal I name (or ask which). Write **pull request**: a `prose` widget with the link, the author's stated intent, and the size; a `callout` for anything risky. Read the diff (`gh pr view`, `gh pr diff`, or the branch), explore the code around it broadly, and read the project's instructions. Then `transition: "start explanation"`.

## 2. Explanation

Write three sections, in this order:

- **background**: the existing system the change touches. I may not know it, so start broad (`glossary_term` for terms, an `architecture` graph for how the parts relate), then narrow to what this change directly depends on. Say that the broad part can be skipped by someone who knows the system.
- **intuition**: the essence of the change, not the full details. A concrete toy example in `examples`, and a `diagram` of before and after (data flow with example data, or a simplified view of the UI for UI changes). Pick one or two diagram styles and reuse them. Use a `callout` for a key concept or an important edge case.
- **code**: a `walkthrough` of the change in the order that makes it understandable (not file order), each step a file, the line range, the excerpt, and what to notice. Add a `diagram` or `architecture` widget where the change reshapes how parts relate.

When I comment on a part, answer there or revise it. Then `transition: "quiz ready"`.

## 3. Quiz

Write **quiz**: a `quiz` widget in `feedback` mode with five questions of medium difficulty: you must understand the substance of the PR to answer, but none is a gotcha. Prefer predictions ("what happens if…") and choices with plausible wrong options. Each option has an explanation that teaches, right or wrong. You receive my answers; if they show a gap, revise the explanation widget they point at. Then `transition: "findings ready"` once I have answered, or when I ask to move on.

## 4. Findings

Write **findings**: a `findings` widget. Each finding has a severity (blocker, major, minor, nit), a path and line, an explanation that says why it matters, and a suggested change when you have one. Do not pad it: no nits that a formatter would catch. I mark each finding Agree, Disagree, or Fixed; when I comment on one, answer it or revise it, keeping the finding's id. Never post anything to the code host. The verdict is mine.
