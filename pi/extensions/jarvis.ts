/** Lifecycle adapter only. All six board tools come from the shared MCP server. */
import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const BASE_URL = (process.env.JARVIS_URL ?? "http://localhost:4000").replace(/\/$/, "");
const BRIDGE = fileURLToPath(new URL("../../agent/jarvis-mcp.mjs", import.meta.url));

export default function jarvis(pi: ExtensionAPI) {
	async function api(ctx: ExtensionContext, path: string, body?: unknown) {
		const response = await fetch(`${BASE_URL}/api${path}`, {
			method: path === "/session" ? "PUT" : "POST",
			headers: {
				"content-type": "application/json",
				"x-jarvis-agent": "pi",
				"x-jarvis-cwd": encodeURIComponent(ctx.cwd),
				"x-jarvis-session": encodeURIComponent(ctx.sessionManager.getSessionId()),
				"x-jarvis-session-name": encodeURIComponent(ctx.sessionManager.getSessionName() ?? ""),
			},
			body: body === undefined ? undefined : JSON.stringify(body),
			signal: AbortSignal.timeout(4_000),
		});
		if (!response.ok) throw new Error(`Jarvis ${response.status}`);
		return response.json() as Promise<{ text?: string | null }>;
	}

	pi.on("session_start", async (_event, ctx) => {
		// Register per conversation, not at extension load: resume/switch must use its real identity.
		pi.registerMcpServer("jarvis", {
			command: "node",
			args: [BRIDGE, "pi"],
			cwd: ctx.cwd,
			env: {
				JARVIS_URL: BASE_URL,
				JARVIS_SESSION_ID: ctx.sessionManager.getSessionId(),
				JARVIS_SESSION_NAME: ctx.sessionManager.getSessionName() ?? "",
			},
			exposure: "codemode",
			description: "Read and update the shared Jarvis task board: goals, tasks, widgets, and comments.",
		});
		await api(ctx, "/session", { state: "idle" }).catch(() => {});
	});

	pi.on("before_agent_start", async (_event, ctx) => {
		// Keep each successful retrieval even if the other fails; the server marks it delivered.
		const comments: string[] = [];
		for (const path of ["/inbox", "/wake"]) {
			try {
				const result = await api(ctx, path);
				if (result.text) comments.push(result.text);
			} catch {
				// Presence and comments must not prevent an ordinary turn when Jarvis is down.
			}
		}
		if (comments.length) {
			return { message: { customType: "jarvis-inbox", content: comments.join("\n\n"), display: true } };
		}
		return undefined;
	});

	pi.on("agent_start", async (_event, ctx) => {
		await api(ctx, "/session", { state: "working" }).catch(() => {});
	});
	pi.on("agent_settled", async (_event, ctx) => {
		await api(ctx, "/session", { state: "idle" }).catch(() => {});
	});
	pi.on("session_shutdown", async (_event, ctx) => {
		pi.unregisterMcpServer("jarvis");
		await api(ctx, "/session", { state: "ended" }).catch(() => {});
	});
}
