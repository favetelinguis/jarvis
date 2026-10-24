#!/usr/bin/env node
// Jarvis board tools as an MCP server over stdio, for Codex and Copilot CLI.
// The agent starts it in the session's working directory; every call goes to
// the Jarvis HTTP API with that directory, so the board is the one pi sees.
// Usage: jarvis-mcp.mjs <codex|copilot>   (JARVIS_URL: default http://localhost:4000)

import { createInterface } from "node:readline";

const AGENT = process.argv[2] ?? "codex";
const BASE_URL = (process.env.JARVIS_URL ?? "http://localhost:4000").replace(/\/$/, "");
const int = (description) => ({ type: "integer", minimum: 1, description });
const obj = (properties, required = []) => ({ type: "object", properties, required });

const widgetOp = obj(
	{
		op: { type: "string", enum: ["add", "update", "move", "delete", "judge"] },
		id: { type: ["integer", "string"], description: "Widget id (update, move, delete, judge), e.g. 12 or W12" },
		section: { type: "string", description: "Section key or label (add; move to another section)" },
		kind: { type: "string", description: "Widget kind (add); see jarvis_catalog" },
		data: { description: "Widget data as an object, matching the kind's fields (add; update replaces all of it)" },
		position: { type: "integer", minimum: 1, description: "1-based position in the section (add, move); default last" },
		question: { type: "string", description: "Quiz question id (judge)" },
		correct: { type: "boolean", description: "Whether the human's free-text answer is correct (judge)" },
		explanation: { type: "string", description: "Why (judge)" },
	},
	["op"],
);

// Keep descriptions in step with pi/extensions/jarvis.ts.
const TOOLS = {
	jarvis_read: {
		description:
			"Read the Jarvis task board of the current project (shared by all worktrees of the repository). " +
			"No arguments: every goal with its tasks one line each, and the live agent sessions. " +
			"goal: the whole goal (its sections as widgets, tasks, comments). " +
			"goal and task: the whole task with its type, step, the transitions out of it, every section as widgets with their ids and part ids, and its comments.",
		schema: obj({ goal: int("Goal number"), task: int("Task number within the goal; requires goal") }),
		readOnly: true,
		request: ({ goal, task }) => {
			if (task && !goal) throw new Error("task requires goal");
			return ["GET", goal ? (task ? `/goals/${goal}/tasks/${task}` : `/goals/${goal}`) : "/overview"];
		},
	},
	jarvis_goal_save: {
		description:
			"Create a goal (omit goal) or rename one (give goal). A goal's Intent, Scope, Glossary, and Decisions are widgets: write them with jarvis_widgets.",
		schema: obj({ goal: int("Goal number to update; omit to create"), title: { type: "string", description: "Goal title; required when creating" }, poc: { type: "boolean", description: "true: mark the goal as built with /poc (unreviewed). Only the human can clear it." } }),
		request: ({ goal, ...fields }) => (goal ? ["PATCH", `/goals/${goal}`, fields] : ["POST", "/goals", fields]),
	},
	jarvis_task_save: {
		description:
			"Create a task in a goal (omit task) or update one (give task). Only the fields you pass change. " +
			"type (on create only; never changes): feature (default), research, pr_review, learn. A task starts in the first step of its type's lifecycle. " +
			"transition: move along the named transition out of the current step (jarvis_read lists them; transitions whose mover is the human are refused, and so are ones whose condition is not met). " +
			"force_step: jump to a step regardless of the lifecycle, for proof-of-concept runs only. " +
			"claim: true records this worktree as the task's Worktree; false releases it. Write sections with jarvis_widgets.",
		schema: obj(
			{
				goal: int("Goal number"),
				task: int("Task number to update; omit to create"),
				title: { type: "string", description: "Task title; required when creating" },
				type: { type: "string", enum: ["feature", "research", "pr_review", "learn"] },
				transition: { type: "string", description: 'Name of a transition out of the current step, e.g. "implemented"' },
				force_step: { type: "string", description: "Step key to jump to, ignoring the lifecycle (proof of concept only)" },
				claim: { type: "boolean", description: "true: claim for this worktree; false: release" },
			},
			["goal"],
		),
		request: ({ goal, task, ...fields }) =>
			task ? ["PATCH", `/goals/${goal}/tasks/${task}`, fields] : ["POST", `/goals/${goal}/tasks`, fields],
	},
	jarvis_widgets: {
		description:
			"Add, update, move, or delete the widgets that make up the sections of a goal (omit task) or a task. All ops of one call succeed or fail together; a failure names the op and every invalid field. " +
			"Keep ids of list items when you update a widget so the human's comments, answers, and confirmations stay attached. " +
			"Prefer visual widgets over prose. judge records your verdict on a human's free-text quiz answer.",
		schema: obj(
			{
				goal: int("Goal number"),
				task: int("Task number; omit to write the goal's own sections"),
				ops: { type: "array", minItems: 1, items: widgetOp, description: "Operations, applied in order" },
			},
			["goal", "ops"],
		),
		request: ({ goal, task, ops }) => ["POST", task ? `/goals/${goal}/tasks/${task}/widgets` : `/goals/${goal}/widgets`, { ops }],
	},
	jarvis_catalog: {
		description:
			"The widget catalog: every widget kind with its fields, parts, and an example, and the sections of goals and of each task type with the widgets recommended for them.",
		schema: obj({}),
		readOnly: true,
		request: () => ["GET", "/catalog"],
	},
	jarvis_comment: {
		description:
			"Leave a note on a goal, or on one of its tasks, that the human sees on the board: a handoff, a decision to double check, or a question that can wait. " +
			"reply_to answers a comment on a widget in its own thread. widget (and part) start a thread on that widget or part. " +
			"Ask questions that block you in the conversation instead.",
		schema: obj(
			{
				goal: int("Goal number"),
				task: int("Task number; omit for the goal"),
				body: { type: "string", description: "Markdown" },
				reply_to: { type: "integer", description: "Id of the comment on a widget that you answer" },
				widget: { type: "integer", description: "Widget id to start a thread on" },
				part: { type: "string", description: "Part id inside the widget, e.g. row:r2" },
			},
			["goal", "body"],
		),
		request: ({ goal, ...body }) => ["POST", `/goals/${goal}/comments`, body],
	},
};

async function call(name, args) {
	const tool = TOOLS[name];
	if (!tool) throw new Error(`unknown tool ${name}`);
	for (const key of tool.schema.required) {
		if (args[key] === undefined) throw new Error(`${key} is required`);
	}
	const [method, path, body] = tool.request(args);
	let response;
	try {
		response = await fetch(`${BASE_URL}/api${path}`, {
			method,
			headers: {
				"content-type": "application/json",
				"x-jarvis-cwd": encodeURIComponent(process.cwd()),
				"x-jarvis-agent": AGENT,
			},
			body: body === undefined ? undefined : JSON.stringify(body),
			signal: AbortSignal.timeout(5000),
		});
	} catch (error) {
		throw new Error(
			`Jarvis server not reachable at ${BASE_URL} (${error.message}). Stop and ask the human to start it (mise run server in the jarvis repository).`,
		);
	}
	const payload = await response.json().catch(() => ({}));
	if (!response.ok) {
		const details = payload.details ? ` ${JSON.stringify(payload.details)}` : "";
		throw new Error(`Jarvis ${response.status}: ${payload.error ?? "request failed"}${details}`);
	}
	return `${payload.text}\nWeb view: ${payload.url}`;
}

async function handle(message) {
	const { id, method, params } = message;
	switch (method) {
		case "initialize":
			return {
				protocolVersion: params?.protocolVersion ?? "2025-06-18",
				capabilities: { tools: {} },
				serverInfo: { name: "jarvis", version: "0.1.0" },
			};
		case "ping":
			return {};
		case "tools/list":
			return {
				tools: Object.entries(TOOLS).map(([name, t]) => ({
					name,
					description: t.description,
					inputSchema: t.schema,
					annotations: t.readOnly ? { readOnlyHint: true, openWorldHint: false } : undefined,
				})),
			};
		case "tools/call":
			try {
				return { content: [{ type: "text", text: await call(params.name, params.arguments ?? {}) }] };
			} catch (error) {
				return { isError: true, content: [{ type: "text", text: error.message }] };
			}
		default:
			if (id === undefined) return undefined; // notification
			throw Object.assign(new Error(`method not found: ${method}`), { code: -32601 });
	}
}

createInterface({ input: process.stdin }).on("line", async (line) => {
	if (!line.trim()) return;
	let message;
	try {
		message = JSON.parse(line);
	} catch {
		return;
	}
	try {
		const result = await handle(message);
		if (message.id !== undefined && result !== undefined) process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: message.id, result }) + "\n");
	} catch (error) {
		if (message.id !== undefined)
			process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: message.id, error: { code: error.code ?? -32603, message: error.message } }) + "\n");
	}
});
