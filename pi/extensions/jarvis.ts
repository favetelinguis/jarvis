/**
 * Jarvis: a shared, live task board for agents and the human, plus a mirror
 * of every session's context in PostgreSQL.
 *
 * - Tools let the agent read and write goals, tasks, and comments in the
 *   Jarvis server; the project and worktree come from the session's cwd.
 * - Session state (working / idle / ended) is reported so the board shows
 *   who is active where.
 * - Human comments left in the web UI are delivered at the start of the
 *   next turn.
 * - After every turn the session file is mirrored into Jarvis, so
 *   /jarvis-resume can bring the exact session back, even after the local
 *   file is gone.
 *
 * Configure the server with JARVIS_URL (default http://localhost:4000).
 */

import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const BASE_URL = (process.env.JARVIS_URL ?? "http://localhost:4000").replace(/\/$/, "");
const HEARTBEAT_MS = 60_000;
const TIMEOUT_MS = 5_000;

type SessionState = "idle" | "working" | "ended";

interface Reply {
	text: string;
	url: string;
	goal?: number;
	task?: number;
}

interface TranscriptSummary {
	id: number;
	harness: "pi" | "codex";
	session_id: string;
	title: string | null;
	lines: number;
	worktree: string | null;
	branch: string | null;
	last_entry_at: string | null;
}

class JarvisError extends Error {}

export default function jarvis(pi: ExtensionAPI) {
	let ctxRef: ExtensionContext | undefined;
	let state: SessionState = "idle";
	let heartbeat: ReturnType<typeof setInterval> | undefined;
	let online: boolean | undefined;
	// Syncs run one at a time so a slow sync never races the next one.
	let syncChain: Promise<unknown> = Promise.resolve();

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

	function syncTranscript(ctx: ExtensionContext): Promise<unknown> {
		const transcriptPath = ctx.sessionManager.getSessionFile();
		if (!transcriptPath) return Promise.resolve(); // --no-session
		const body = {
			session_id: ctx.sessionManager.getSessionId(),
			transcript_path: transcriptPath,
			cwd: ctx.cwd,
		};
		syncChain = syncChain.then(() => api(ctx, "POST", "/transcripts/sync?harness=pi", body)).catch(() => {});
		return syncChain;
	}

	function stopHeartbeat() {
		if (heartbeat) clearInterval(heartbeat);
		heartbeat = undefined;
	}

	// ---------------------------------------------------------------- lifecycle

	pi.on("session_start", async (_event, ctx) => {
		ctxRef = ctx;
		online = undefined;
		reportState(ctx, "idle");
		quietly(syncTranscript(ctx));
		stopHeartbeat();
		heartbeat = setInterval(() => {
			if (ctxRef) quietly(api(ctxRef, "PUT", "/session", { state }));
		}, HEARTBEAT_MS);
	});

	pi.on("agent_start", async (_event, ctx) => reportState(ctx, "working"));

	pi.on("turn_end", async (_event, ctx) => {
		quietly(syncTranscript(ctx));
	});

	pi.on("agent_end", async (_event, ctx) => {
		reportState(ctx, "idle");
		quietly(syncTranscript(ctx));
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		stopHeartbeat();
		// Awaited so the final turn and the ended state are recorded before pi exits.
		await syncTranscript(ctx);
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
		"Update a task's status in Jarvis the moment it changes, so the board stays live.",
	];

	pi.registerTool({
		name: "jarvis_read",
		label: "Jarvis read",
		description:
			"Read the Jarvis task board of the current project (shared by all worktrees of the repository). " +
			"No arguments: every goal with its tasks one line each, and the live agent sessions. " +
			"goal: the whole goal (Intent, Scope, Glossary, Decisions, tasks, comments). " +
			"goal and task: the whole task with every section and its comments.",
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

	const markdown = (description: string) => Type.Optional(Type.String({ description }));

	pi.registerTool({
		name: "jarvis_goal_save",
		label: "Jarvis goal",
		description:
			"Create a goal (omit goal) or update one (give goal). Only the fields you pass change; pass an empty string to clear one. " +
			"Sections are markdown, written as in the workflow's goal file format.",
		parameters: Type.Object({
			goal: Type.Optional(Type.Integer({ minimum: 1, description: "Goal number to update; omit to create" })),
			title: Type.Optional(Type.String({ description: "Goal title; required when creating" })),
			intent: markdown("The problem, who has it, and what is better once the goal is complete"),
			scope: markdown("Markdown list with **In:** and **Out:** items"),
			glossary: markdown("Markdown list of **Term:** meaning"),
			decisions: markdown("Markdown list of cross-task decisions with their reasons"),
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
			"Create a task in a goal (omit task) or update one (give task). Only the fields you pass change; pass an empty string to clear one. " +
			"Status: todo = requirements written, ready = sketch written and awaiting implementation, done = implemented and reviewed. " +
			"claim: true records this worktree as the task's Worktree; false releases it. Sections are markdown.",
		parameters: Type.Object({
			goal: Type.Integer({ minimum: 1, description: "Goal number" }),
			task: Type.Optional(Type.Integer({ minimum: 1, description: "Task number to update; omit to create" })),
			title: Type.Optional(Type.String({ description: "Task title; required when creating" })),
			status: Type.Optional(StringEnum(["todo", "ready", "done"] as const)),
			claim: Type.Optional(Type.Boolean({ description: "true: claim for this worktree; false: release" })),
			intent: markdown("Why the task exists and what someone can do once it merges"),
			requirements: markdown("Markdown list of **R1** ... requirements"),
			examples: markdown("Markdown table of concrete examples"),
			constraints: markdown("Constraints with their source, or None."),
			assumptions: markdown("Assumptions, or None."),
			out_of_scope: markdown("What this task does not do, and which task does"),
			open_questions: markdown("Open questions marked (requirements) or (design), or None."),
			sketch: markdown("Files the sketch adds or changes"),
			tests: markdown("Markdown list mapping each requirement to its tests"),
		}),
		async execute(_id, { goal, task, ...fields }, signal, _onUpdate, ctx) {
			const result = task
				? await api<Reply>(ctx, "PATCH", `/goals/${goal}/tasks/${task}`, fields, signal)
				: await api<Reply>(ctx, "POST", `/goals/${goal}/tasks`, fields, signal);
			return reply(result);
		},
	});

	pi.registerTool({
		name: "jarvis_comment",
		label: "Jarvis comment",
		description:
			"Leave a note on a goal, or on one of its tasks, that the human sees on the board: a handoff, a decision to double check, or a question that can wait. " +
			"Ask questions that block you in the conversation instead.",
		parameters: Type.Object({
			goal: Type.Integer({ minimum: 1, description: "Goal number" }),
			task: Type.Optional(Type.Integer({ minimum: 1, description: "Task number; omit for the goal" })),
			body: Type.String({ description: "Markdown" }),
		}),
		async execute(_id, { goal, task, body }, signal, _onUpdate, ctx) {
			return reply(await api<Reply>(ctx, "POST", `/goals/${goal}/comments`, { task, body }, signal));
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

	pi.registerCommand("jarvis-resume", {
		description: "Restore a session of this project from Jarvis and resume it (Codex sessions print their resume command)",
		handler: async (_args, ctx) => {
			let transcripts: TranscriptSummary[];
			try {
				transcripts = (await api<{ transcripts: TranscriptSummary[] }>(ctx, "GET", "/transcripts")).transcripts;
			} catch (error) {
				ctx.ui.notify((error as Error).message, "error");
				return;
			}
			if (transcripts.length === 0) {
				ctx.ui.notify("Jarvis has no sessions for this project yet.", "info");
				return;
			}

			const labels = transcripts.map((t) => {
				const when = t.last_entry_at ? t.last_entry_at.slice(0, 16).replace("T", " ") : "";
				const where = t.worktree ? `${t.worktree}${t.branch ? `@${t.branch}` : ""}` : "";
				return `[${t.harness}] ${(t.title ?? t.session_id).slice(0, 70)} · ${where} · ${t.lines} lines · ${when}`;
			});
			const choice = await ctx.ui.select("Restore which session?", labels);
			if (choice === undefined) return;
			const picked = transcripts[labels.indexOf(choice)];

			let restored: { status: string; path: string; backup: string | null; command: string };
			try {
				restored = await api(ctx, "POST", `/transcripts/${picked.id}/restore`);
			} catch (error) {
				ctx.ui.notify((error as Error).message, "error");
				return;
			}

			if (restored.backup) ctx.ui.notify(`The file on disk differed; kept it as ${restored.backup}`, "warning");
			if (picked.harness !== "pi") {
				ctx.ui.notify(`Restored. Resume it with:\n${restored.command}`, "info");
				return;
			}
			await ctx.switchSession(restored.path);
		},
	});
}
