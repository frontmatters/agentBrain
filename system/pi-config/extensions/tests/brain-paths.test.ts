import assert from "node:assert/strict";
import test from "node:test";

test("brainPath resolves paths under AGENTBRAIN_DIR", async () => {
	process.env.AGENTBRAIN_DIR = "/tmp/agentbrain-test-root";
	const mod = await import("../brain-paths");

	assert.equal(mod.brainDir(), "/tmp/agentbrain-test-root");
	assert.equal(
		mod.brainPath("local", "sessions", "session-journal.md"),
		"/tmp/agentbrain-test-root/local/sessions/session-journal.md",
	);
});

test("configured external vault is used for vault paths", async () => {
	const mod = await import("../brain-paths");
	process.env.AGENTBRAIN_VAULT = "/tmp/agentbrain-user-vault";

	assert.equal(mod.vaultDir(), "/tmp/agentbrain-user-vault");
	assert.equal(
		mod.brainPath("vault", "learnings", "patterns.md"),
		"/tmp/agentbrain-user-vault/learnings/patterns.md",
	);
	assert.equal(
		mod.brainPath("local", "projects", "demo", "index.md"),
		"/tmp/agentbrain-user-vault/projects/demo/index.md",
	);

	delete process.env.AGENTBRAIN_VAULT;
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
