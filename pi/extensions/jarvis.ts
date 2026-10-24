/**
 * Jarvis: a shared, live task board for agents and the human.
 *
 * - Tools let the agent read and write goals, tasks, and comments in the
 *   Jarvis server; the project and worktree come from the session's cwd.
 * - Session state (working / idle / ended) is reported so the board shows
 *   who is active where.
 * - Human comments left in the web UI are delivered at the start of the
 *   next turn. Comments on a widget, or on a part of one, wake an idle
 *   session within seconds: the extension polls /api/wake and starts a turn.
 *
 * Configure the server with JARVIS_URL (default http://localhost:4000).
 */

import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const BASE_URL = (process.env.JARVIS_URL ?? "http://localhost:4000").replace(/\/$/, "");
const HEARTBEAT_MS = 60_000;
const TIMEOUT_MS = 5_000;
const WAKE_POLL_MS = 2_000;

type SessionState = "idle" | "working" | "ended";

interface Reply {
	text: string;
	url: string;
	goal?: number;
	task?: number;
}

class JarvisError extends Error {}

export default function jarvis(pi: ExtensionAPI) {
	let ctxRef: ExtensionContext | undefined;
	let state: SessionState = "idle";
	let heartbeat: ReturnType<typeof setInterval> | undefined;
	let wakePoll: ReturnType<typeof setInterval> | undefined;
	let waking = false;
	let online: boolean | undefined;

	function headers(ctx: ExtensionContext): Record<string, string> {
		const h: Record<string, string> = {
			"content-type": "application/json",
			"x-jarvis-cwd": encodeURIComponent(ctx.cwd),
			"x-jarvis-session": encodeURIComponent(ctx.sessionManager.getSessionId()),
		};
		const name = ctx.sessionManager.getSessionName();
		if (name) h["x-jarvis-session-name"] = encodeURIComponent(name);
		return h;
	}

	function setOnline(ctx: ExtensionContext, value: boolean) {
		if (online === value) return;
		online = value;
		if (ctx.hasUI) ctx.ui.setStatus("jarvis", value ? "jarvis ●" : "jarvis ○ offline");
	}

	async function api<T>(ctx: ExtensionContext, method: string, path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
		const timeout = AbortSignal.timeout(TIMEOUT_MS);
		let response: Response;
		try {
			response = await fetch(`${BASE_URL}/api${path}`, {
				method,
				headers: headers(ctx),
				body: body === undefined ? undefined : JSON.stringify(body),
				signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
			});
		} catch (error) {
			setOnline(ctx, false);
			throw new JarvisError(
				`Jarvis server not reachable at ${BASE_URL} (${(error as Error).message}). ` +
					"Ask the human to start it (mise run server in the jarvis repository).",
			);
		}
		setOnline(ctx, true);
		const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
		if (!response.ok) {
			const details = payload.details ? ` ${JSON.stringify(payload.details)}` : "";
			throw new JarvisError(`Jarvis ${response.status}: ${payload.error ?? "request failed"}${details}`);
		}
		return payload as T;
	}

	/** Fire-and-forget calls from lifecycle events: Jarvis being down must never disturb the session. */
	function quietly(promise: Promise<unknown>) {
		promise.catch(() => {});
	}

	function reportState(ctx: ExtensionContext, next: SessionState) {
		state = next;
		quietly(api(ctx, "PUT", "/session", { state: next }));
	}

	function stopHeartbeat() {
		if (heartbeat) clearInterval(heartbeat);
		heartbeat = undefined;
		if (wakePoll) clearInterval(wakePoll);
		wakePoll = undefined;
	}

	/** An idle session asks Jarvis for comments on widgets; a busy one asks again when its turn ends. */
	async function wakeIfCommented() {
		const ctx = ctxRef;
		if (!ctx || waking || !ctx.isIdle()) return;
		waking = true;
		try {
			const wake = await api<{ count: number; text: string | null }>(ctx, "POST", "/wake");
			if (wake.count > 0 && wake.text) pi.sendUserMessage(wake.text);
		} catch {
			// Jarvis is down: try again at the next poll.
		} finally {
			waking = false;
		}
	}

	// ---------------------------------------------------------------- lifecycle

	pi.on("session_start", async (_event, ctx) => {
		ctxRef = ctx;
		online = undefined;
		reportState(ctx, "idle");
		stopHeartbeat();
		heartbeat = setInterval(() => {
			if (ctxRef) quietly(api(ctxRef, "PUT", "/session", { state }));
		}, HEARTBEAT_MS);
		wakePoll = setInterval(() => quietly(wakeIfCommented()), WAKE_POLL_MS);
	});

	pi.on("agent_start", async (_event, ctx) => reportState(ctx, "working"));

	pi.on("agent_end", async (_event, ctx) => {
		reportState(ctx, "idle");
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		stopHeartbeat();
		// Awaited so the ended state is recorded before pi exits.
		await api(ctx, "PUT", "/session", { state: "ended" }).catch(() => {});
		ctxRef = undefined;
	});

	pi.on("before_agent_start", async (_event, ctx) => {
		try {
			const inbox = await api<{ count: number; text: string | null }>(ctx, "POST", "/inbox");
			if (inbox.count > 0 && inbox.text) {
				return { message: { customType: "jarvis-inbox", content: inbox.text, display: true } };
			}
		} catch {
			// Jarvis is down: the turn goes ahead without the inbox.
		}
		return undefined;
	});

	// -------------------------------------------------------------------- tools

	const reply = (r: Reply) => ({
		content: [{ type: "text" as const, text: `${r.text}\nWeb view: ${r.url}` }],
		details: { url: r.url, goal: r.goal, task: r.task },
	});

	const guidelines = [
		"Goals and tasks live in Jarvis, a live board the human watches. Read with jarvis_read and write with jarvis_goal_save / jarvis_task_save; never keep task files on disk.",
		"Refer to goals and tasks as Goal N and Task N.M, and give the human the web view link when you create or finish one.",
		"A task has a type (feature, research, pr_review, learn) and moves along its lifecycle with jarvis_task_save transition; jarvis_read lists the transitions out of its step and who moves each.",
		"Write goal and task sections as widgets with jarvis_widgets, never as long markdown; call jarvis_catalog for the widget kinds. Prefer visual widgets (requirement cards, examples tables, diagrams, comparisons, quizzes) over prose.",
		"A message titled 'Comments on widgets in Jarvis' is the human commenting on one widget or part: change that widget, or answer in its thread with jarvis_comment reply_to. If it is only a question, answer it without changing the widget.",
	];

	pi.registerTool({
		name: "jarvis_read",
		label: "Jarvis read",
		description:
			"Read the Jarvis task board of the current project (shared by all worktrees of the repository). " +
			"No arguments: every goal with its tasks one line each, and the live agent sessions. " +
			"goal: the whole goal (its sections as widgets, tasks, comments). " +
			"goal and task: the whole task with its type, step, the transitions out of it, every section as widgets with their ids and part ids, and its comments.",
		promptSnippet: "Read goals and tasks from the Jarvis board",
		promptGuidelines: guidelines,
		parameters: Type.Object({
			goal: Type.Optional(Type.Integer({ minimum: 1, description: "Goal number" })),
			task: Type.Optional(Type.Integer({ minimum: 1, description: "Task number within the goal; requires goal" })),
		}),
		annotations: { readOnlyHint: true, openWorldHint: false },
		async execute(_id, params, signal, _onUpdate, ctx) {
			if (params.task && !params.goal) throw new JarvisError("task requires goal");
			const path = params.goal
				? params.task
					? `/goals/${params.goal}/tasks/${params.task}`
					: `/goals/${params.goal}`
				: "/overview";
			return reply(await api<Reply>(ctx, "GET", path, undefined, signal));
		},
	});

	pi.registerTool({
		name: "jarvis_goal_save",
		label: "Jarvis goal",
		description:
			"Create a goal (omit goal) or rename one (give goal). A goal's Intent, Scope, Glossary, and Decisions are widgets: write them with jarvis_widgets.",
		parameters: Type.Object({
			goal: Type.Optional(Type.Integer({ minimum: 1, description: "Goal number to update; omit to create" })),
			title: Type.Optional(Type.String({ description: "Goal title; required when creating" })),
		}),
		async execute(_id, { goal, ...fields }, signal, _onUpdate, ctx) {
			const result = goal
				? await api<Reply>(ctx, "PATCH", `/goals/${goal}`, fields, signal)
				: await api<Reply>(ctx, "POST", "/goals", fields, signal);
			return reply(result);
		},
	});

	pi.registerTool({
		name: "jarvis_task_save",
		label: "Jarvis task",
		description:
			"Create a task in a goal (omit task) or update one (give task). Only the fields you pass change. " +
			"type (on create only; never changes): feature (default), research, pr_review, learn. A task starts in the first step of its type's lifecycle. " +
			"transition: move along the named transition out of the current step (jarvis_read lists them; transitions whose mover is the human are refused, and so are ones whose condition is not met). " +
			"force_step: jump to a step regardless of the lifecycle, for proof-of-concept runs only. " +
			"claim: true records this worktree as the task's Worktree; false releases it. Write sections with jarvis_widgets.",
		parameters: Type.Object({
			goal: Type.Integer({ minimum: 1, description: "Goal number" }),
			task: Type.Optional(Type.Integer({ minimum: 1, description: "Task number to update; omit to create" })),
			title: Type.Optional(Type.String({ description: "Task title; required when creating" })),
			type: Type.Optional(StringEnum(["feature", "research", "pr_review", "learn"] as const)),
			transition: Type.Optional(Type.String({ description: "Name of a transition out of the current step, e.g. \"implemented\"" })),
			force_step: Type.Optional(Type.String({ description: "Step key to jump to, ignoring the lifecycle (proof of concept only)" })),
			claim: Type.Optional(Type.Boolean({ description: "true: claim for this worktree; false: release" })),
		}),
		async execute(_id, { goal, task, ...fields }, signal, _onUpdate, ctx) {
			const result = task
				? await api<Reply>(ctx, "PATCH", `/goals/${goal}/tasks/${task}`, fields, signal)
				: await api<Reply>(ctx, "POST", `/goals/${goal}/tasks`, fields, signal);
			return reply(result);
		},
	});

	const widgetOp = Type.Object({
		op: StringEnum(["add", "update", "move", "delete", "judge"] as const),
		id: Type.Optional(Type.Union([Type.Integer(), Type.String()], { description: "Widget id (update, move, delete, judge), e.g. 12 or W12" })),
		section: Type.Optional(Type.String({ description: "Section key or label (add; move to another section)" })),
		kind: Type.Optional(Type.String({ description: "Widget kind (add); see jarvis_catalog" })),
		data: Type.Optional(Type.Any({ description: "Widget data as an object, matching the kind's fields (add; update replaces all of it)" })),
		position: Type.Optional(Type.Integer({ minimum: 1, description: "1-based position in the section (add, move); default last" })),
		question: Type.Optional(Type.String({ description: "Quiz question id (judge)" })),
		correct: Type.Optional(Type.Boolean({ description: "Whether the human's free-text answer is correct (judge)" })),
		explanation: Type.Optional(Type.String({ description: "Why (judge)" })),
	});

	pi.registerTool({
		name: "jarvis_widgets",
		label: "Jarvis widgets",
		description:
			"Add, update, move, or delete the widgets that make up the sections of a goal (omit task) or a task. All ops of one call succeed or fail together; a failure names the op and every invalid field. " +
			"Keep ids of list items when you update a widget so the human's comments, answers, and confirmations stay attached. " +
			"Prefer visual widgets over prose. judge records your verdict on a human's free-text quiz answer.",
		promptSnippet: "Write widgets into the sections of a Jarvis goal or task",
		parameters: Type.Object({
			goal: Type.Integer({ minimum: 1, description: "Goal number" }),
			task: Type.Optional(Type.Integer({ minimum: 1, description: "Task number; omit to write the goal's own sections" })),
			ops: Type.Array(widgetOp, { minItems: 1, description: "Operations, applied in order" }),
		}),
		async execute(_id, { goal, task, ops }, signal, _onUpdate, ctx) {
			const path = task ? `/goals/${goal}/tasks/${task}/widgets` : `/goals/${goal}/widgets`;
			return reply(await api<Reply>(ctx, "POST", path, { ops }, signal));
		},
	});

	pi.registerTool({
		name: "jarvis_catalog",
		label: "Jarvis catalog",
		description:
			"The widget catalog: every widget kind with its fields, parts, and an example, and the sections of goals and of each task type with the widgets recommended for them.",
		parameters: Type.Object({}),
		annotations: { readOnlyHint: true, openWorldHint: false },
		async execute(_id, _params, signal, _onUpdate, ctx) {
			return reply(await api<Reply>(ctx, "GET", "/catalog", undefined, signal));
		},
	});

	pi.registerTool({
		name: "jarvis_comment",
		label: "Jarvis comment",
		description:
			"Leave a note on a goal, or on one of its tasks, that the human sees on the board: a handoff, a decision to double check, or a question that can wait. " +
			"reply_to answers a comment on a widget in its own thread. widget (and part) start a thread on that widget or part. " +
			"Ask questions that block you in the conversation instead.",
		parameters: Type.Object({
			goal: Type.Integer({ minimum: 1, description: "Goal number" }),
			task: Type.Optional(Type.Integer({ minimum: 1, description: "Task number; omit for the goal" })),
			body: Type.String({ description: "Markdown" }),
			reply_to: Type.Optional(Type.Integer({ description: "Id of the comment on a widget that you answer" })),
			widget: Type.Optional(Type.Integer({ description: "Widget id to start a thread on" })),
			part: Type.Optional(Type.String({ description: "Part id inside the widget, e.g. row:r2" })),
		}),
		async execute(_id, { goal, ...body }, signal, _onUpdate, ctx) {
			return reply(await api<Reply>(ctx, "POST", `/goals/${goal}/comments`, body, signal));
		},
	});

	// ----------------------------------------------------------------- commands

	pi.registerCommand("jarvis", {
		description: "Show the Jarvis board of this project",
		handler: async (_args, ctx) => {
			try {
				const overview = await api<Reply>(ctx, "GET", "/overview");
				ctx.ui.notify(`${overview.text}\n${overview.url}`, "info");
			} catch (error) {
				ctx.ui.notify((error as Error).message, "error");
			}
		},
	});
}
