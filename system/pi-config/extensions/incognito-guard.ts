/**
 * Incognito Guard (Pi extension)
 *
 * Pi-side mirror of the Claude Code PreToolUse hook
 * (system/addons/incognito/claude-pretooluse-guard.sh).
 *
 * When agentBrain is in incognito mode (read-only this session), BLOCK
 * agent-initiated Write/Edit/MultiEdit to knowledge notes under the vault's
 * `local/` tree. Fires on `tool_call` (before the tool runs) so the write is
 * prevented, not merely flagged after the fact.
 *
 * Scope: only `local/` knowledge is blocked. Code edits (system/, scripts/,
 * root config) stay allowed — incognito stops NEW KNOWLEDGE, not all work.
 * The MCP write tools (brain_save_learning / brain_project_update) are guarded
 * separately in agentbrain-mcp/src/write.ts; this handles direct file writes.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { extractFilePath, isIncognito, isVaultLocalWrite } from "./brain-paths";

const WRITE_TOOLS = new Set([
	"Write",
	"write",
	"Edit",
	"edit",
	"MultiEdit",
	"multiedit",
]);

const BLOCK_REASON =
	"BLOCKED: agentBrain is in incognito mode (read-only this session). " +
	"Writing knowledge to local/ is suppressed. Consulting the brain still " +
	"works. To persist knowledge, turn it off first: /incognito off";

/**
 * Pure decision: should this tool call be blocked?
 * The incognito flag and the vault-path predicate are injected so the
 * decision order (tool → mode → path) is unit-testable without a real vault
 * (see tests/incognito-guard.test.ts).
 */
export function shouldBlockWrite(
	toolName: string,
	filePath: string,
	deps: {
		incognito: () => boolean;
		isVaultLocalWrite: (path: string) => boolean;
	},
): boolean {
	if (!WRITE_TOOLS.has(toolName)) return false;
	if (!deps.incognito()) return false;
	if (!filePath) return false;
	return deps.isVaultLocalWrite(filePath);
}

export default function incognitoGuard(pi: ExtensionAPI): void {
	pi.on("tool_call", (event) => {
		const filePath = extractFilePath(event.input);
		const block = shouldBlockWrite(event.toolName, filePath, {
			incognito: isIncognito,
			isVaultLocalWrite,
		});
		return block ? { block: true, reason: BLOCK_REASON } : undefined;
	});
}
