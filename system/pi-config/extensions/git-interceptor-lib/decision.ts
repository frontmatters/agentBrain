/**
 * Pure decision logic for the git-interceptor extension.
 *
 * Kept free of Pi API imports so it can be unit-tested without a Pi runtime
 * (see tests/git-interceptor.test.ts). The extension entrypoint
 * (../git-interceptor.ts) only wires this decision into Pi's tool_call event.
 */

export const GIT_ENV_PREFIX =
	"export GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true GIT_MERGE_AUTOEDIT=no\n";

const NO_VERIFY_RE = /--no-verify\b/;

export const BLOCK_REASON =
	"BLOCKED: --no-verify is not allowed. Git hooks exist for a reason. " +
	"Do not attempt to bypass them. Instead: fix the underlying issue that " +
	"is causing the hook to fail, or ask the user for help.";

export type GitCommandDecision =
	| { action: "pass" }
	| { action: "block"; reason: string }
	| { action: "rewrite"; command: string };

/**
 * Decide what to do with a bash command before it runs:
 * - not a git command        → pass through untouched
 * - contains `--no-verify`   → block (hook bypass prevention)
 * - any other git command    → rewrite with no-op editor env vars
 *                              (editor hang prevention)
 */
export function decideGitCommand(command: string): GitCommandDecision {
	if (!command.includes("git")) return { action: "pass" };
	if (NO_VERIFY_RE.test(command)) {
		return { action: "block", reason: BLOCK_REASON };
	}
	return { action: "rewrite", command: GIT_ENV_PREFIX + command };
}
