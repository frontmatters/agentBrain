import assert from "node:assert/strict";
import * as fsp from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import test from "node:test";
import { listMarkdownFiles } from "../agentbrain-lib/files";

async function makeTree(): Promise<string> {
	const root = await fsp.mkdtemp(path.join(os.tmpdir(), "ab-files-"));
	// A plain directory with a note.
	await fsp.mkdir(path.join(root, "real"));
	await fsp.writeFile(path.join(root, "real", "a.md"), "plain note");
	// A note that lives behind a SYMLINKED directory — this is the vault's
	// `local/` shape. readdir() reports the link as isDirectory()===false.
	const target = await fsp.mkdtemp(path.join(os.tmpdir(), "ab-target-"));
	await fsp.writeFile(path.join(target, "b.md"), "note behind a symlink");
	await fsp.symlink(target, path.join(root, "linked"), "dir");
	return root;
}

test("listMarkdownFiles follows symlinked directories (regression: local/ was invisible)", async () => {
	const root = await makeTree();
	const files = await listMarkdownFiles(root);
	const names = files.map((f) => path.basename(f)).sort();

	assert.ok(names.includes("a.md"), "plain-directory note must be found");
	assert.ok(
		names.includes("b.md"),
		"note behind a symlinked directory must be found — else the whole private vault is unsearchable",
	);
});

test("listMarkdownFiles does not loop on a symlink cycle", async () => {
	const root = await makeTree();
	// A symlink pointing back at an ancestor would spin the walker forever
	// without the realpath cycle guard.
	await fsp.symlink(root, path.join(root, "loop"), "dir");

	const files = await listMarkdownFiles(root);
	assert.ok(
		files.length >= 2,
		"walk terminates and still returns the real notes despite the cycle",
	);
});
