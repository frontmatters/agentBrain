import assert from "node:assert/strict";
import test from "node:test";
import {
	BLOCK_REASON,
	GIT_ENV_PREFIX,
	decideGitCommand,
} from "../git-interceptor-lib/decision";

// The extension entrypoint (git-interceptor.ts) has a runtime import of
// @earendil-works/pi-coding-agent (isToolCallEventType), which is only
// resolvable inside a Pi runtime — so these tests target the extracted pure
// decision logic in git-interceptor-lib/decision.ts instead.

test("non-git commands pass through untouched", () => {
	assert.deepEqual(decideGitCommand("ls -la"), { action: "pass" });
	assert.deepEqual(decideGitCommand("npm test"), { action: "pass" });
});

test("--no-verify outside a git command still passes (no git in command)", () => {
	assert.deepEqual(decideGitCommand("echo --no-verify"), { action: "pass" });
});

test("plain git commands are rewritten with no-op editor env prefix", () => {
	const cmd = "git commit -m 'msg'";
	const decision = decideGitCommand(cmd);
	assert.equal(decision.action, "rewrite");
	assert.ok(decision.action === "rewrite"); // narrow for TS
	assert.equal(decision.command, GIT_ENV_PREFIX + cmd);
	assert.ok(decision.command.includes("GIT_EDITOR=true"));
});

test("git commit --no-verify is blocked with the explanation", () => {
	const decision = decideGitCommand("git commit --no-verify -m 'msg'");
	assert.equal(decision.action, "block");
	assert.ok(decision.action === "block"); // narrow for TS
	assert.equal(decision.reason, BLOCK_REASON);
	assert.match(decision.reason, /--no-verify is not allowed/);
});

test("--no-verify is blocked in any git subcommand position", () => {
	assert.equal(decideGitCommand("git push --no-verify").action, "block");
	assert.equal(
		decideGitCommand("cd repo && git commit --no-verify").action,
		"block",
	);
});

test("--no-verify requires a word boundary (no false positive on longer flags)", () => {
	// Hypothetical flag sharing the prefix must not trigger the block.
	const decision = decideGitCommand("git run --no-verifyfoo");
	assert.equal(decision.action, "rewrite");
});
