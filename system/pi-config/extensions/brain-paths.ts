/**
 * brain-paths.ts — Shared path helpers for agentBrain Pi extensions.
 *
 * Provides a single, Pi-lens-safe way to resolve paths inside the agentBrain
 * vault.  Import `brainPath` instead of calling `path.join(BRAIN_DIR, ...)`
 * directly — this eliminates per-call `pi-lens-ignore: ts-path-traversal`
 * suppressions across extensions.
 *
 * Usage:
 *   import { brainPath, BRAIN_DIR } from "./brain-paths";
 *   const journal = brainPath("local", "sessions", "session-journal.md");
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/**
 * Root of the agentBrain vault.
 *
 * Resolution order (matches what every other agent already does via the alias):
 *   1. AGENTBRAIN_DIR env var (explicit override, useful for testing)
 *   2. ~/agentBrain — the alias maintained by `brain use dev|live` (scripts/brain.sh)
 *   3. ~/Developer/agentBrain — legacy hardcoded fallback for systems without the alias
 *
 * The symlink string itself is kept (not realpath-resolved) so that flipping
 * the alias at runtime is picked up on the next filesystem call.
 */
function resolveBrainDir(): string {
	if (process.env.AGENTBRAIN_DIR) {
		return process.env.AGENTBRAIN_DIR;
	}
	const alias = path.join(os.homedir(), "agentBrain");
	if (fs.existsSync(alias)) {
		return alias;
	}
	return path.join(os.homedir(), "Developer", "agentBrain");
}

// pi-lens-ignore: ts-path-traversal
export const BRAIN_DIR = path.resolve(resolveBrainDir());

/**
 * Build an absolute path inside the agentBrain vault.
 * Throws when a segment would escape the vault via `..` or an absolute path.
 */
// pi-lens-ignore: ts-path-traversal
export function brainPath(...segments: string[]): string {
	const resolved = path.resolve(BRAIN_DIR, ...segments);
	const relative = path.relative(BRAIN_DIR, resolved);
	const insideBrain =
		relative === "" ||
		(!relative.startsWith("..") && !path.isAbsolute(relative));
	if (!insideBrain) {
		throw new Error(`Path escapes agentBrain root: ${segments.join("/")}`);
	}
	return resolved;
}

/**
 * True when agentBrain is in incognito mode (read-only this session).
 *
 * Single source of truth for the Pi side, mirroring the bash
 * `system/addons/incognito/is-incognito.sh` and the MCP server's
 * `assertNotIncognito()`. The flag lives in the ACTIVE vault, so it flips with
 * `brain use dev|live`. Robust by construction: never throws, only ever true/false.
 */
export function isIncognito(): boolean {
	try {
		return fs.existsSync(brainPath("local", "sessions", ".incognito"));
	} catch {
		return false;
	}
}

/**
 * True when `filePath` is a write into the active vault's `local/` knowledge tree.
 * Realpath-compared so it holds whether the agent writes via the `~/agentBrain`
 * symlink or the resolved vault path. Used by the incognito guard to scope blocks
 * to knowledge writes (code edits under system/, scripts/, root stay allowed).
 */
export function isVaultLocalWrite(filePath: string): boolean {
	try {
		const localRoot = brainPath("local");
		if (!fs.existsSync(localRoot)) return false;
		const realLocal = fs.realpathSync(localRoot);
		const targetDir = path.dirname(path.resolve(filePath));
		if (!fs.existsSync(targetDir)) return false;
		const realDir = fs.realpathSync(targetDir);
		return realDir === realLocal || realDir.startsWith(realLocal + path.sep);
	} catch {
		return false;
	}
}

/**
 * Extract a file path from a tool input of unknown shape.
 * Pi's write/edit tool inputs carry the target as `file_path` or `path`;
 * anything else (or a non-string value) yields "".
 */
export function extractFilePath(input: unknown): string {
	if (typeof input !== "object" || input === null) return "";
	// Safe cast: narrowed to a non-null object above; we only read two
	// optional keys and validate their type before use.
	const record = input as Record<string, unknown>;
	const candidate = record.file_path ?? record.path;
	return typeof candidate === "string" ? candidate : "";
}

/**
 * No-op extension factory.
 *
 * This module is a *helper*, not an extension, but it lives in the
 * Pi-scanned `extensions/` directory (it must sit next to the extensions
 * that `import { brainPath } from "./brain-paths"`). Pi's loader tries to
 * load every `.ts` here as an extension and would otherwise log
 * "does not export a valid factory function". Exporting an empty factory
 * that registers nothing makes Pi load it silently. Do not remove.
 */
export default function brainPathsNoopExtension(): void {
	// Intentionally empty: no extension behaviour to register.
}
