// Integration test: proves the wiring, not just the pure helpers. It mocks the model
// call (complete) and pi's extension API, sets a goal through the real /goal handler,
// then fires the session_start hook — and asserts the goal is actually deregistered.
import assert from "node:assert/strict";
import { readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test, { mock } from "node:test";

const LOG_PATH = join(tmpdir(), "goal-log-integration-test.jsonl");
process.env.GOAL_LOG_PATH = LOG_PATH;

// The refiner and the evaluator both go through `complete`. Branch on the system
// prompt: SMART refine → a verifiable condition; goal evaluation → "met".
// node:test module mocking needs the --experimental-test-module-mocks flag
// (wired in scripts/tests/test-pi-extensions.sh). The mock is installed once, before
// any test imports goal — node:test does not auto-reset module mocks between
// tests, so re-mocking the same specifier throws ERR_INVALID_STATE.
mock.module("@earendil-works/pi-ai/compat", {
	namedExports: {
		complete: async (_model: unknown, req: { systemPrompt: string }) => {
			if (req.systemPrompt.includes("SMART")) {
				return { content: [{ type: "text", text: '{"smart":"tests green in packages/x","verifiable":true,"missing":[],"note":"scoped"}' }] };
			}
			return { content: [{ type: "text", text: '{"ok":true,"reason":"transcript shows: 16 pass, 0 fail"}' }], usage: { in: 1, out: 1 } };
		},
	},
});

// Minimal fakes for pi's ExtensionAPI + ExtensionContext. Imports the real goal
// extension (after the compat mock is installed) and wires it into the fake pi.
async function harness() {
	const goalExtension = (await import("../goal")).default;
	const hooks: Record<string, Array<(e: unknown, c: unknown) => unknown>> = {};
	const appended: Array<{ type: string; data: { goal?: { condition: string } } }> = [];
	const commands: Record<string, { handler: (a: string, c: unknown) => Promise<void> }> = {};
	const status: Record<string, string | undefined> = {};
	const notes: string[] = [];

	const pi = {
		registerCommand: (name: string, def: { handler: (a: string, c: unknown) => Promise<void> }) => { commands[name] = def; },
		registerTool: () => {},
		on: (event: string, fn: (e: unknown, c: unknown) => unknown) => { (hooks[event] ||= []).push(fn); },
		appendEntry: (type: string, data: { goal?: { condition: string } }) => { appended.push({ type, data }); },
		sendMessage: () => {},
	};

	const ctx = {
		hasUI: true,
		ui: { setStatus: (k: string, v?: string) => { status[k] = v; }, notify: (m: string) => { notes.push(m); } },
		model: { provider: "test", id: "m" },
		modelRegistry: { getApiKeyAndHeaders: async () => ({ ok: true, apiKey: "k", headers: {}, env: {} }) },
		sessionManager: {
			getEntries: () => appended.map((e) => ({ type: "custom", customType: e.type, data: e.data })),
			getBranch: () => [],
		},
	};

	// biome-ignore lint: fakes intentionally loose
	goalExtension(pi as any);
	return { hooks, appended, commands, status, notes, ctx };
}

test("integration: /goal sets a SMART goal, then session_start auto-clears it once met", async () => {
	rmSync(LOG_PATH, { force: true });
	const h = await harness();

	// 1. Set a goal through the real handler. The SMART gate refines + activates it.
	await h.commands.goal.handler("make the tests pass", h.ctx as unknown as never);
	const activated = h.appended.at(-1)?.data.goal;
	assert.equal(activated?.condition, "tests green in packages/x", "goal is stored with the SMART condition");
	assert.equal(h.status.goal, "goal: tests green in packages/x", "status shows the active goal");

	// 2. Fire the session_start hook. It re-evaluates and, since the mock verdict is
	//    ok, must call clearGoal — persisting goal:undefined and clearing the status.
	await h.hooks.session_start[0](null, h.ctx);

	assert.equal(h.appended.at(-1)?.data.goal, undefined, "goal is deregistered (persisted state is empty)");
	assert.equal(h.status.goal, undefined, "status indicator is cleared");
	assert.ok(h.notes.some((n) => n.includes("auto-cleared on resume")), "user is told the goal auto-cleared");

	// 3. Both lifecycle events are in the durable goal log.
	const log = readFileSync(LOG_PATH, "utf8").trim().split("\n").map((l) => JSON.parse(l) as Record<string, unknown>);
	const setLine = log.find((e) => e.event === "set");
	const clearedLine = log.find((e) => e.event === "cleared");
	assert.equal(setLine?.condition, "tests green in packages/x", "set event logged with the SMART condition");
	assert.equal(setLine?.original, "make the tests pass", "set event keeps the original wording");
	assert.equal(clearedLine?.outcome, "achieved-on-resume", "cleared event logged with the outcome");
});

test("per-context: the log lands under GOAL_LOG_DIR/<context>/goals.jsonl", async () => {
	const base = join(tmpdir(), "goal-logs-ctx-test");
	rmSync(base, { recursive: true, force: true });
	process.env.GOAL_LOG_PATH = undefined as unknown as string; // let the per-context path win
	delete process.env.GOAL_LOG_PATH;
	process.env.GOAL_LOG_DIR = base;
	process.env.GOAL_LOG_CONTEXT = "Client Space";

	try {
		const h = await harness();
		await h.commands.goal.handler("make the tests pass", h.ctx as unknown as never);

		const expected = join(base, "client-space", "goals.jsonl"); // "Client Space" → slug
		const log = readFileSync(expected, "utf8");
		assert.match(log, /"event":"set"/, "set event written to the per-context file");
		assert.match(log, /"context":"Client Space"/, "the context is recorded on the entry");
	} finally {
		process.env.GOAL_LOG_PATH = LOG_PATH;
		delete process.env.GOAL_LOG_DIR;
		delete process.env.GOAL_LOG_CONTEXT;
	}
});
