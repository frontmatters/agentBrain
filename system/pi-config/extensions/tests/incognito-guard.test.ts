import assert from "node:assert/strict";
import test from "node:test";
import { extractFilePath } from "../brain-paths";
import { shouldBlockWrite } from "../incognito-guard";

// shouldBlockWrite takes its two environment predicates (incognito flag,
// vault-path check) as injected deps, so the decision order
// (tool → mode → path) is testable without a real vault on disk.

const incognitoOn = () => true;
const incognitoOff = () => false;
const inVault = (_path: string) => true;
const outsideVault = (_path: string) => false;

test("non-write tools are never blocked, even in incognito", () => {
	for (const tool of ["Read", "read", "bash", "grep", ""]) {
		assert.equal(
			shouldBlockWrite(tool, "/vault/local/learnings/x.md", {
				incognito: incognitoOn,
				isVaultLocalWrite: inVault,
			}),
			false,
			`tool '${tool}' must not be blocked`,
		);
	}
});

test("write tools are not blocked when incognito is off", () => {
	assert.equal(
		shouldBlockWrite("Write", "/vault/local/learnings/x.md", {
			incognito: incognitoOff,
			isVaultLocalWrite: inVault,
		}),
		false,
	);
});

test("write tools in incognito are blocked for vault-local paths", () => {
	for (const tool of ["Write", "write", "Edit", "edit", "MultiEdit", "multiedit"]) {
		assert.equal(
			shouldBlockWrite(tool, "/vault/local/learnings/x.md", {
				incognito: incognitoOn,
				isVaultLocalWrite: inVault,
			}),
			true,
			`tool '${tool}' must be blocked`,
		);
	}
});

test("write tools in incognito stay allowed outside the vault local/ tree", () => {
	assert.equal(
		shouldBlockWrite("Write", "/repo/system/some-code.ts", {
			incognito: incognitoOn,
			isVaultLocalWrite: outsideVault,
		}),
		false,
	);
});

test("an empty file path is never blocked", () => {
	assert.equal(
		shouldBlockWrite("Write", "", {
			incognito: incognitoOn,
			isVaultLocalWrite: inVault,
		}),
		false,
	);
});

test("path check is not consulted when incognito is off (decision order)", () => {
	let pathChecked = false;
	shouldBlockWrite("Write", "/vault/local/x.md", {
		incognito: incognitoOff,
		isVaultLocalWrite: () => {
			pathChecked = true;
			return true;
		},
	});
	assert.equal(pathChecked, false, "vault-path predicate must not run");
});

test("extractFilePath reads file_path, then path, and rejects non-strings", () => {
	assert.equal(extractFilePath({ file_path: "/a.md" }), "/a.md");
	assert.equal(extractFilePath({ path: "/b.md" }), "/b.md");
	assert.equal(
		extractFilePath({ file_path: "/a.md", path: "/b.md" }),
		"/a.md",
		"file_path wins over path",
	);
	assert.equal(extractFilePath({ file_path: 42 }), "");
	assert.equal(extractFilePath({}), "");
	assert.equal(extractFilePath(null), "");
	assert.equal(extractFilePath(undefined), "");
	assert.equal(extractFilePath("just-a-string"), "");
});

test("incognito-guard extension loads and exports default factory", async () => {
	const mod = await import("../incognito-guard");
	assert.equal(typeof mod.default, "function");
});
