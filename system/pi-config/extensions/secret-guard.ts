/** Pre-tool secret guard; delegates matching to the Claude hook to avoid regex drift. */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { brainDir } from "./brain-paths";

const SCRIPT = join(brainDir(), "system/addons/secret-guard/claude-pretooluse-secret-guard.py");
const FAILURE = "Blocked: secret guard could not scan tool input.";

/** Pure decision seam; scanner can be replaced without a real agent installation. */
export function secretGuardDecision(input: unknown, scanner: (input: unknown) => string | null): { block: true; reason: string } | undefined {
	const reason = scanner(input);
	return reason ? { block: true, reason } : undefined;
}

function scan(input: unknown): string | null {
	const result = spawnSync("python3", [SCRIPT], {
		input: JSON.stringify({ tool_input: input }),
		encoding: "utf8",
		timeout: 5000,
		maxBuffer: 1024 * 1024,
	});
	if (result.status === 0) return null;
	if (result.status === 2) return result.stderr.trim() || FAILURE;
	return FAILURE; // missing scanner or timeout must not silently disable protection
}

export default function secretGuard(pi: ExtensionAPI): void {
	pi.on("tool_call", (event) => secretGuardDecision(event.input, scan));
}
