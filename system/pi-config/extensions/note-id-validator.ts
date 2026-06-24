/**
 * Note ID Validator (Pi extension)
 *
 * Layer 1 of the agent-discipline enforcement framework, Pi-side mirror of
 * the Claude Code PostToolUse hook (scripts/claude-code-validate-note-id-hook.sh).
 *
 * Fires on tool_result for Write/Edit tools. If the file written is a brain note
 * under local/<dir>/<slug>.md with an `id:` field, validates that the id matches
 * uuid5-gen.sh for the path. On mismatch: surfaces a system-style error so the
 * agent sees the mistake and retries with the correct id.
 *
 * Shared validator: scripts/validate-note-id.sh (called via spawnSync). The
 * validator handles all exempt-paths + path-derivation logic; this extension
 * is just the Pi-side trigger.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { BRAIN_DIR } from "./brain-paths";

const WRITE_TOOLS = new Set(["Write", "write", "Edit", "edit", "MultiEdit", "multiedit"]);

export default function (pi: ExtensionAPI) {
	pi.on("tool_result" as any, (event: any) => {
		const toolName: string = event?.toolName ?? "";
		if (!WRITE_TOOLS.has(toolName)) return undefined;

		const filePath: string =
			event?.input?.file_path ?? event?.input?.path ?? "";
		if (!filePath) return undefined;

		const validator = join(BRAIN_DIR, "scripts", "validate-note-id.sh");
		const r = spawnSync("bash", [validator, filePath], {
			encoding: "utf8",
			timeout: 5000,
		});

		// Exit 0 = valid or not-applicable. Exit 1 = mismatch detected.
		// Anything else (timeout, missing validator) — silent no-op to avoid blocking
		// unrelated tool flows on infrastructure issues.
		if (r.status === 1 && r.stderr) {
			// Surface to the agent. Pi displays stderr from extensions as visible warnings;
			// the agent sees the diagnostic and can re-issue the Write with the correct id.
			console.error(`\n[note-id-validator] ${r.stderr.trim()}\n`);
		}
		return undefined;
	});
}
