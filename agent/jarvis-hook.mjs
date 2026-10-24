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

const sessionId = input.session_id ?? input.sessionId ?? `${agent}-${process.ppid}`;
const headers = {
	"content-type": "application/json",
	"x-jarvis-cwd": encodeURIComponent(input.cwd ?? process.cwd()),
	"x-jarvis-session": encodeURIComponent(sessionId),
	"x-jarvis-agent": agent,
};

const post = async (method, path, body) => {
	const response = await fetch(`${BASE_URL}/api${path}`, { method, headers, body: body && JSON.stringify(body), signal: AbortSignal.timeout(4000) });
	return response.json();
};

try {
	if (event === "start") {
		await post("PUT", "/session", { state: "working" });
		const [inbox, wake] = [await post("POST", "/inbox"), await post("POST", "/wake")];
		const text = [inbox.text, wake.text].filter(Boolean).join("\n\n");
		if (text) console.log(text);
	} else {
		await post("PUT", "/session", { state: event === "end" ? "ended" : "idle" });
	}
} catch {}
