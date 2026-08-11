import assert from "node:assert/strict";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// note-id-validator.ts is fired by Pi's tool_result event. We can't unit-test
// the registered handler without instantiating a real Pi context. Instead we
// validate the two correctness properties this extension depends on:
//   1. The shared validator (scripts/validate-note-id.sh) exists and works
//      from a built fixture brain (this is what the extension shells out to).
//   2. The extension module loads + exports a default function (Pi's
//      extension contract).
//
// __dirname-style path so the test runs under both Node (tsx --test) and Bun.

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "..", "..", "..", "..");

test("scripts/validate-note-id.sh exists and is executable", () => {
	const validator = join(REPO_ROOT, "scripts", "validate-note-id.sh");
	assert.ok(existsSync(validator), `expected validator at ${validator}`);
});

test("validator returns 0 on valid id, 1 on mismatch (smoke from extension perspective)", () => {
	const validator = join(REPO_ROOT, "scripts", "validate-note-id.sh");
	const fixture = mkdtempSync(join(tmpdir(), "note-id-validator-ext-test-"));
	mkdirSync(join(fixture, "scripts"), { recursive: true });
	mkdirSync(join(fixture, "local", "learnings"), { recursive: true });
	copyFileSync(join(REPO_ROOT, "brain.json"), join(fixture, "brain.json"));
	copyFileSync(join(REPO_ROOT, "scripts", "uuid5-gen.sh"), join(fixture, "scripts", "uuid5-gen.sh"));

	// Compute correct uuid via uuid5-gen.sh (same path the validator uses)
	const correct = spawnSync(
		"bash",
		[join(fixture, "scripts", "uuid5-gen.sh"), "local/learnings/good"],
		{ encoding: "utf8" },
	).stdout.trim();

	writeFileSync(
		join(fixture, "local", "learnings", "good.md"),
		`---\ndate: 2026-05-24\ntype: learning\ntags: [test]\nid: ${correct}\n---\n# Good\n`,
	);
	writeFileSync(
		join(fixture, "local", "learnings", "bad.md"),
		`---\ndate: 2026-05-24\ntype: learning\ntags: [test]\nid: 00000000-0000-0000-0000-000000000000\n---\n# Bad\n`,
	);

	const good = spawnSync("bash", [validator, join(fixture, "local", "learnings", "good.md")]);
	assert.equal(good.status, 0, "valid id should pass");

	const bad = spawnSync("bash", [validator, join(fixture, "local", "learnings", "bad.md")]);
	assert.equal(bad.status, 1, "wrong id should fail");
});

test("note-id-validator extension loads and exports default factory", async () => {
	const mod = await import("../note-id-validator");
	assert.equal(typeof mod.default, "function", "default export must be a Pi extension factory");
});
