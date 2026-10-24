import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:http";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { after, test } from "node:test";

const root = fileURLToPath(new URL("../../", import.meta.url));
const requests = [];
let reply = () => ({ text: "board", url: "http://board.test" });
const server = createServer(async (req, res) => {
	let raw = "";
	for await (const chunk of req) raw += chunk;
	const request = { path: req.url, method: req.method, headers: req.headers, body: raw ? JSON.parse(raw) : undefined };
	requests.push(request);
	const payload = reply(request, res);
	if (payload !== undefined) res.end(typeof payload === "string" ? payload : JSON.stringify(payload));
});
server.listen(0, "127.0.0.1");
await once(server, "listening");
const base = `http://127.0.0.1:${server.address().port}`;
after(() => { server.closeAllConnections(); server.close(); });

function bridge(t, agent, env = {}) {
	const child = spawn(process.execPath, ["agent/jarvis-mcp.mjs", agent], {
		cwd: root, env: { ...process.env, CODEX_THREAD_ID: "", COPILOT_AGENT_SESSION_ID: "", JARVIS_SESSION_ID: "", JARVIS_URL: base, ...env },
	});
	let id = 0;
	const pending = new Map();
	createInterface({ input: child.stdout }).on("line", line => {
		const message = JSON.parse(line);
		pending.get(message.id)?.(message.result);
		pending.delete(message.id);
	});
	t.after(async () => { const done = once(child, "exit"); child.kill(); await done; });
	return (method, params = {}) => new Promise(resolve => {
		pending.set(++id, resolve);
		child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
	});
}

const toolNames = ["jarvis_read", "jarvis_goal_save", "jarvis_task_save", "jarvis_widgets", "jarvis_catalog", "jarvis_comment"];
const calls = [
	["jarvis_read", {}, "GET", "/api/overview"],
	["jarvis_goal_save", { title: "Goal" }, "POST", "/api/goals"],
	["jarvis_task_save", { goal: 2, task: 6, title: "Task" }, "PATCH", "/api/goals/2/tasks/6"],
	["jarvis_widgets", { goal: 2, ops: [{ op: "add", section: "intent", kind: "prose", data: { text: "Intent" } }] }, "POST", "/api/goals/2/widgets"],
	["jarvis_catalog", {}, "GET", "/api/catalog"],
	["jarvis_comment", { goal: 2, body: "Note" }, "POST", "/api/goals/2/comments"],
];
let canonicalTools;
for (const agent of ["pi", "codex", "copilot"]) {
	test(`${agent}: shared MCP schemas, routing, and explicit conversation identity`, { timeout: 10000 }, async t => {
		reply = () => ({ text: "board", url: "http://board.test" });
		const env = agent === "pi" ? { JARVIS_SESSION_ID: "pi-1" } : agent === "copilot" ? { COPILOT_AGENT_SESSION_ID: "copilot-1" } : {};
		const rpc = bridge(t, agent, env);
		const initialized = await rpc("initialize", { protocolVersion: "2025-11-25" });
		assert.ok(initialized.capabilities.tools);
		const { tools } = await rpc("tools/list");
		assert.deepEqual(tools.map(t => t.name), toolNames);
		if (canonicalTools) assert.deepEqual(tools, canonicalTools);
		canonicalTools = tools;
		for (const [name, args, method, path] of calls) {
			const result = await rpc("tools/call", { name, arguments: args, _meta: agent === "codex" ? { threadId: "codex-1" } : {} });
			assert.equal(result.isError, undefined);
			assert.equal(result.content[0].text, "board\nWeb view: http://board.test");
			const request = requests.at(-1);
			assert.equal(request.method, method);
			assert.equal(request.path, path);
			assert.equal(decodeURIComponent(request.headers["x-jarvis-cwd"]), root.replace(/\/$/, ""));
			assert.equal(request.headers["x-jarvis-agent"], agent);
			assert.equal(request.headers["x-jarvis-session"], `${agent}-1`);
		}
	});
}

test("MCP identity follows the calling Codex thread, not the last active session", { timeout: 10000 }, async t => {
	const rpc = bridge(t, "codex");
	for (const id of ["thread-a", "thread-b", "thread-a"]) {
		await rpc("tools/call", { name: "jarvis_read", _meta: { threadId: id } });
		assert.equal(requests.at(-1).headers["x-jarvis-session"], id);
	}
});

test("MCP reports missing identity, invalid arguments, server rejection, and malformed replies as errors", { timeout: 10000 }, async t => {
	const rpc = bridge(t, "pi");
	let result = await rpc("tools/call", { name: "jarvis_read" });
	assert.equal(result.isError, true);
	assert.match(result.content[0].text, /session identity/i);
	const identified = bridge(t, "pi", { JARVIS_SESSION_ID: "pi-errors" });
	result = await identified("tools/call", { name: "jarvis_read", arguments: { task: 1 } });
	assert.equal(result.isError, true);
	reply = (_req, res) => { res.statusCode = 422; return { error: "invalid widget", details: { field: "kind" } }; };
	result = await identified("tools/call", { name: "jarvis_read" });
	assert.equal(result.isError, true);
	assert.match(result.content[0].text, /invalid widget.*kind/);
	reply = (_req, res) => { res.destroy(); return undefined; };
	result = await identified("tools/call", { name: "jarvis_read" });
	assert.equal(result.isError, true);
	assert.match(result.content[0].text, /not reachable/);
	reply = () => "not json";
	result = await identified("tools/call", { name: "jarvis_read" });
	assert.equal(result.isError, true);
	reply = () => ({ text: "board", url: "http://board.test" });
});

test("MCP requests have a bounded deadline and do not retry a timed-out mutation", { timeout: 10000 }, async t => {
	requests.length = 0;
	reply = () => undefined;
	const rpc = bridge(t, "pi", { JARVIS_SESSION_ID: "pi-timeout" });
	const result = await rpc("tools/call", { name: "jarvis_goal_save", arguments: { title: "Timeout" } });
	assert.equal(result.isError, true);
	assert.match(result.content[0].text, /not reachable/);
	assert.equal(requests.length, 1);
});

async function hook(agent, event, input, env = {}) {
	const child = spawn(process.execPath, ["agent/jarvis-hook.mjs", agent, event], {
		cwd: root, env: { ...process.env, JARVIS_URL: base, ...env },
	});
	let stdout = "";
	child.stdout.on("data", data => stdout += data);
	const done = once(child, "exit");
	child.stdin.end(JSON.stringify(input));
	const [code] = await done;
	assert.equal(code, 0);
	return stdout.trim();
}

for (const agent of ["codex", "copilot"]) {
	test(`${agent}: turn hooks deliver plain and anchored comments in the harness format`, async () => {
		requests.length = 0;
		reply = req => ({ text: req.path === "/api/inbox" ? "Plain comment" : req.path === "/api/wake" ? "Anchored comment" : null });
		const input = { cwd: root, sessionId: `${agent}-hook`, transformedPrompt: "Original prompt" };
		const output = await hook(agent, "start", input);
		if (agent === "copilot") {
			assert.equal(JSON.parse(output).modifiedTransformedPrompt, "Original prompt\n\nPlain comment\n\nAnchored comment");
		} else assert.equal(output, "Plain comment\n\nAnchored comment");
		assert.deepEqual(requests.map(r => r.path), ["/api/session", "/api/inbox", "/api/wake"]);
		assert.equal(requests[0].body.state, "working");
		assert.ok(requests.every(r => r.headers["x-jarvis-session"] === `${agent}-hook`));
		await hook(agent, "stop", input);
		assert.equal(requests.at(-1).body.state, "idle");
		await hook(agent, "end", input);
		assert.equal(requests.at(-1).body.state, "ended");
		assert.equal(requests.length, 5);
		reply = (req, res) => {
			if (req.path === "/api/wake") { res.statusCode = 503; return { error: "offline" }; }
			return { text: req.path === "/api/inbox" ? "Taken plain comment" : null };
		};
		const partial = await hook(agent, "start", input);
		assert.ok(partial.includes("Taken plain comment"));
		reply = () => ({ text: null });
		assert.equal(await hook(agent, "start", input), "");
		reply = (_req, res) => { res.statusCode = 503; return { error: "offline" }; };
		assert.equal(await hook(agent, "start", input), "");
	});
}

test("legacy Copilot hooks cannot consume undeliverable comments", async () => {
	requests.length = 0;
	assert.equal(await hook("copilot", "start", { sessionId: "old-hook", prompt: "Original" }), "");
	assert.equal(requests.length, 0);
});

test("pi: lifecycle-only extension registers on-demand MCP with the actual session, supplies next-turn comments, and ends cleanly", async () => {
	process.env.JARVIS_URL = base;
	const { default: jarvis } = await import("../../pi/extensions/jarvis.ts");
	const handlers = new Map();
	const registrations = [];
	const pi = {
		on: (name, handler) => handlers.set(name, handler),
		registerMcpServer: (name, config) => registrations.push({ name, config }),
		unregisterMcpServer: name => registrations.push({ removed: name }),
	};
	jarvis(pi);
	const ctx = { cwd: root, sessionManager: { getSessionId: () => "pi-session", getSessionName: () => "My session" } };
	requests.length = 0;
	reply = req => ({ count: 1, text: req.path === "/api/inbox" ? "Plain" : req.path === "/api/wake" ? "Anchored" : null });
	await handlers.get("session_start")({}, ctx);
	assert.equal(registrations[0].name, "jarvis");
	assert.equal(registrations[0].config.exposure, "codemode");
	assert.equal(registrations[0].config.env.JARVIS_SESSION_ID, "pi-session");
	assert.equal(registrations[0].config.cwd, root);
	assert.ok(registrations[0].config.args[0].endsWith("agent/jarvis-mcp.mjs"));
	const before = await handlers.get("before_agent_start")({}, ctx);
	assert.equal(before.message.content, "Plain\n\nAnchored");
	await handlers.get("agent_start")({}, ctx);
	await handlers.get("agent_settled")({}, ctx);
	assert.equal(requests.at(-1).body.state, "idle");
	await handlers.get("session_shutdown")({}, ctx);
	assert.equal(requests.at(-1).body.state, "ended");
	assert.deepEqual(requests.map(r => r.path), ["/api/session", "/api/inbox", "/api/wake", "/api/session", "/api/session", "/api/session"]);
	assert.ok(requests.every(r => r.headers["x-jarvis-session"] === "pi-session"));
	assert.ok(!handlers.has("agent_end"));
	reply = (req, res) => {
		if (req.path === "/api/wake") { res.statusCode = 500; return { error: "offline" }; }
		return { text: "Taken plain comment" };
	};
	assert.equal((await handlers.get("before_agent_start")({}, ctx)).message.content, "Taken plain comment");
	reply = () => ({ count: 0, text: null });
	assert.equal(await handlers.get("before_agent_start")({}, ctx), undefined);
	reply = (_req, res) => { res.statusCode = 500; return { error: "offline" }; };
	assert.equal(await handlers.get("before_agent_start")({}, ctx), undefined);
	await handlers.get("agent_start")({}, ctx);
});
