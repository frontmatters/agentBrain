/**
 * Note ID Validator (Pi extension)
 *
 * Layer 1 of the agent-discipline enforcement framework, Pi-side mirror of the
 * Claude Code hooks. Enforces that a brain note's `id:` matches uuid5-gen.sh for
 * its path. Two handlers give parity with (and, for Write, exceed) the CC side:
 *
 *   1. tool_call  — PRE-write BLOCK. For a Write we know the full proposed body,
 *      so a wrong id is caught and the write is prevented outright (returns
 *      { block: true }). This is the parity fix: previously the Pi side only
 *      logged a warning on tool_result, so a bad id slipped through where the
 *      Claude Code PostToolUse hook (exit 2) would have forced a retry.
 *   2. tool_result — POST-write advisory net for Edit/MultiEdit (partial diffs
 *      whose id line we can't see pre-write) and anything the pre-write check
 *      couldn't resolve. The file exists here, so it's validated directly.
 *
 * The commit-time gate (scripts/validate-staged-note-ids.sh) is the true
 * agent-agnostic backstop; these handlers are fast per-write feedback.
 *
 * Shared validator: scripts/validate-note-id.sh (called via spawnSync). It owns
 * all path-derivation + exempt-path + uuid5 logic; `--content-file` lets it
 * validate a candidate body before the target file exists. This extension never
 * duplicates that logic — zero formula drift.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BRAIN_DIR, extractFilePath } from "./brain-paths";

const WRITE_TOOLS = new Set([
	"Write",
	"write",
	"Edit",
	"edit",
	"MultiEdit",
	"multiedit",
]);

const VALIDATOR = join(BRAIN_DIR, "scripts", "validate-note-id.sh");

/**
 * The full proposed file body, if this tool call carries one. Only the Write
 * tool does — Edit/MultiEdit are partial diffs whose frontmatter id line may be
 * absent, so we can't validate their result pre-write. Returns null otherwise.
 */
function proposedContent(toolName: string, input: unknown): string | null {
	if (toolName !== "Write" && toolName !== "write") return null;
	if (typeof input !== "object" || input === null) return null;
	const content = (input as Record<string, unknown>).content;
	return typeof content === "string" ? content : null;
}

/**
 * Run the shared validator. When `contentFile` is given, the id is read from it
 * and validated as if written to `filePath` (pre-write). Returns the diagnostic
 * on mismatch (validator exit 1), else null (valid / not-applicable).
 */
function validate(filePath: string, contentFile: string | null): string | null {
	const args = contentFile
		? [VALIDATOR, filePath, "--content-file", contentFile]
		: [VALIDATOR, filePath];
	const r = spawnSync("bash", args, { encoding: "utf8", timeout: 5000 });
	return r.status === 1 && r.stderr ? r.stderr.trim() : null;
}

export default function (pi: ExtensionAPI) {
	// Layer 1a — pre-write BLOCK (Write only; full body known).
	pi.on("tool_call", (event) => {
		if (!WRITE_TOOLS.has(event.toolName)) return undefined;
		const filePath = extractFilePath(event.input);
		if (!filePath || !filePath.endsWith(".md")) return undefined;
		const content = proposedContent(event.toolName, event.input);
		if (content === null) return undefined; // Edit/MultiEdit → post-write net

		let dir: string | null = null;
		try {
			dir = mkdtempSync(join(tmpdir(), "abnid-"));
			const candidate = join(dir, "candidate.md");
			writeFileSync(candidate, content);
			const err = validate(filePath, candidate);
			if (err) {
				return {
					block: true,
					reason:
						`[note-id-validator] ${err}\n` +
						"Scaffold notes with `bash scripts/new-note.sh <type> <path>` — never hand-type the id.",
				};
			}
		} catch {
			// Never block on infrastructure failure; the commit-time gate backstops.
			return undefined;
		} finally {
			if (dir) {
				try {
					rmSync(dir, { recursive: true, force: true });
				} catch {
					/* ignore cleanup failure */
				}
			}
		}
		return undefined;
	});

	// Layer 1b — post-write advisory net (Edit/MultiEdit + unresolved cases).
	pi.on("tool_result", (event) => {
		if (!WRITE_TOOLS.has(event.toolName)) return undefined;
		const filePath = extractFilePath(event.input);
		if (!filePath) return undefined;
		const err = validate(filePath, null);
		if (err) {
			// Pi surfaces extension stderr as a visible warning; the agent sees it
			// and can re-issue the write with the correct id.
			console.error(`\n[note-id-validator] ${err}\n`);
		}
		return undefined;
	});
}
