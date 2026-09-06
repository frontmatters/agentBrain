/**
 * Git Interceptor
 *
 * Two guards for agent-driven git commands:
 *
 * 1. Editor hang prevention — Sets GIT_EDITOR, GIT_SEQUENCE_EDITOR to `true`
 *    (no-op) and GIT_MERGE_AUTOEDIT to `no` so git never spawns an interactive
 *    editor (nvim, vim, etc.) that would hang the bash process.
 *
 * 2. Hook bypass prevention — Blocks any command containing `--no-verify` so
 *    the agent cannot circumvent git hooks (pre-commit, commit-msg, etc.).
 *    The agent should fix hook failures or ask the human for help instead.
 *
 * The decision logic lives in git-interceptor-lib/decision.ts (pure,
 * unit-tested); this file only wires it into Pi's tool_call event.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { decideGitCommand } from "./git-interceptor-lib/decision";

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", (event) => {
		if (!isToolCallEventType("bash", event)) return;

		const decision = decideGitCommand(event.input.command);
		if (decision.action === "block") {
			return { block: true, reason: decision.reason };
		}
		if (decision.action === "rewrite") {
			event.input.command = decision.command;
		}
	});
}
