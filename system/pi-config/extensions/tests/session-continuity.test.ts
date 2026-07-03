import assert from "node:assert/strict";
import test from "node:test";

async function loadSessionContinuity() {
	process.env.AGENTBRAIN_DIR = "/tmp/agentbrain-session-test";
	return import("../session-continuity");
}

test("selectSessionArchiveTarget builds archive path from timestamp and pid suffix", async () => {
	const { selectSessionArchiveTarget } = await loadSessionContinuity();
	const now = new Date(2026, 4, 18, 21, 22, 23);
	const selected = selectSessionArchiveTarget(
		now,
		() => "abcd",
		() => false,
	);

	assert.equal(selected.base, "20260518-212223-abcd");
	assert.equal(selected.archiveMonth, "2026-05");
	assert.equal(
		selected.relWithoutExt,
		"local/sessions/archive/2026-05/20260518-212223-abcd",
	);
	assert.equal(
		selected.target,
		"/tmp/agentbrain-session-test/local/sessions/archive/2026-05/20260518-212223-abcd.md",
	);
});

test("selectSessionArchiveTarget retries colliding names", async () => {
	const { selectSessionArchiveTarget } = await loadSessionContinuity();
	const now = new Date(2026, 4, 18, 21, 22, 23);
	const suffixes = ["aaaa", "bbbb"];
	const selected = selectSessionArchiveTarget(
		now,
		() => suffixes.shift() ?? "cccc",
		(file) => file.endsWith("20260518-212223-aaaa.md"),
	);

	assert.equal(selected.base, "20260518-212223-bbbb");
});

test("selectSessionArchiveTarget fails after repeated collisions", async () => {
	const { selectSessionArchiveTarget } = await loadSessionContinuity();
	const now = new Date(2026, 4, 18, 21, 22, 23);

	assert.throws(
		() =>
			selectSessionArchiveTarget(
				now,
				() => "same",
				() => true,
			),
		/Could not allocate unique session archive filename/,
	);
});
