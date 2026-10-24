---
name: poc
description: "POC mode - implement a whole goal in one go, skipping the strict specify/design/review workflow, so the human can see the result"
disable-model-invocation: true
---
Argument: "[Goal N, or what to build]"
You are building a proof of concept. Input: the text the human typed after naming this workflow

Normal workflow rules are suspended: do not wait for requirements to be confirmed, do not stop for /design or /impl-review, and do not ask me questions unless something is contradictory or impossible. I want to see the result, fast.

## Jarvis

Goals and tasks live in Jarvis (`jarvis_read`, `jarvis_task_save`, `jarvis_widgets`, `jarvis_comment`); never in files. If a Jarvis tool reports that the server is unreachable, stop and tell me.

- If the input is a goal, read it with `jarvis_read` and work through **all** its tasks in order, in this worktree. If it is a description, create the goal and one task per vertical slice first (`jarvis_goal_save`, `jarvis_task_save`, with requirement cards in `jarvis_widgets`), then work through them.
- Claim each task (`claim: true`). Move it through its lifecycle as you go with `jarvis_task_save` `force_step` (this is the POC override: it ignores the human-only transitions): Design when you start it, Implementation while you code, Review when it works, Done when the check passes. The board then shows where you are.
- Leave a `jarvis_comment` on each task when it is done: what you built, what you left out, what to look at.

## Build

1. Read the project's instructions and the code around the goal first, so the result looks like the rest of the codebase.
2. Per task: write tests for the requirements, make them pass, run the project's check command. Tests are not optional, but a thorough review round is.
3. Prefer working end to end over polish. When a requirement is unclear, choose the simplest reading and note it in the task's comment.
4. When all tasks are done, run the project's full check and report: what exists, how to see it, anything you could not run, and what you would improve first. Keep the report short.
