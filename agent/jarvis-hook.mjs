#!/usr/bin/env node
// Presence and comment delivery for Codex and Copilot CLI, run by their hooks.
// Usage: jarvis-hook.mjs <codex|copilot> <start|stop|end>
//   start: the turn begins: report "working", print the human's comments
//          (plain ones, and anchored ones addressed to this session)
//   stop:  the turn ended: report "idle"
//   end:   the session ended
// The hook's stdin is the agent's JSON (session id, cwd). Jarvis being down
// must never disturb the turn, so every failure is swallowed.

const [agent, event] = process.argv.slice(2);
const BASE_URL = (process.env.JARVIS_URL ?? "http://localhost:4000").replace(/\/$/, "");

let input = {};
try {
	let raw = "";
	for await (const chunk of process.stdin) raw += chunk;
	input = JSON.parse(raw || "{}");
} catch {}

// Legacy userPromptSubmitted hooks ignore output. Never consume comments through that event.
if (agent === "copilot" && event === "start" && typeof input.transformedPrompt !== "string") process.exit(0);

const sessionId = input.session_id ?? input.sessionId ??
	(agent === "copilot" ? process.env.COPILOT_AGENT_SESSION_ID : process.env.CODEX_THREAD_ID);
// A process id is not a conversation id: missing identity must not create a phantom session.
if (!sessionId) process.exit(0);
const headers = {
	"content-type": "application/json",
	"x-jarvis-cwd": encodeURIComponent(input.cwd ?? process.cwd()),
	"x-jarvis-session": encodeURIComponent(sessionId),
	"x-jarvis-agent": agent,
};

// The whole hook must finish before the harness's 10-second hook timeout.
const deadline = AbortSignal.timeout(8_000);
const post = async (method, path, body) => {
	const response = await fetch(`${BASE_URL}/api${path}`, {
		method, headers, body: body && JSON.stringify(body),
		signal: AbortSignal.any([deadline, AbortSignal.timeout(4_000)]),
	});
	if (!response.ok) throw new Error(`Jarvis ${response.status}`);
	return response.json();
};

try {
	if (event === "start") {
		await post("PUT", "/session", { state: "working" });
		const comments = [];
		for (const path of ["/inbox", "/wake"]) {
			try {
				const result = await post("POST", path);
				if (result.text) comments.push(result.text);
			} catch {
				// Do not lose an already-taken comment if the other retrieval fails.
			}
		}
		const text = comments.join("\n\n");
		if (text) {
			if (agent === "copilot") {
				console.log(JSON.stringify({ modifiedTransformedPrompt: `${input.transformedPrompt}\n\n${text}` }));
			} else console.log(text);
		}
	} else {
		await post("PUT", "/session", { state: event === "end" ? "ended" : "idle" });
	}
} catch {}
