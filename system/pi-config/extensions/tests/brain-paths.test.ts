import assert from "node:assert/strict";
import test from "node:test";

test("brainPath resolves paths under AGENTBRAIN_DIR", async () => {
	process.env.AGENTBRAIN_DIR = "/tmp/agentbrain-test-root";
	const mod = await import("../brain-paths");

	assert.equal(mod.BRAIN_DIR, "/tmp/agentbrain-test-root");
	assert.equal(
		mod.brainPath("local", "sessions", "session-journal.md"),
		"/tmp/agentbrain-test-root/local/sessions/session-journal.md",
	);
});

test("brainPath rejects traversal outside AGENTBRAIN_DIR", async () => {
	const mod = await import("../brain-paths");

	assert.throws(
		() => mod.brainPath("..", "outside.md"),
		/Path escapes agentBrain root/,
	);
	assert.throws(
		() => mod.brainPath("/tmp/outside.md"),
		/Path escapes agentBrain root/,
	);
});

test("brain-paths default export is a no-op Pi extension factory", async () => {
	const mod = await import("../brain-paths");

	assert.equal(typeof mod.default, "function");
	assert.equal(mod.default(), undefined);
});
