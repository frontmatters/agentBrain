import * as path from "node:path";
import { brainPath, BRAIN_DIR } from "../brain-paths";

// pi-lens-ignore: ts-path-traversal — all paths validated against BRAIN_DIR before I/O
export function normalizeBrainPath(input: string): string {
	const withoutAt = input.trim().replace(/^@/, "");
	const absolute = path.isAbsolute(withoutAt)
		? withoutAt
		: brainPath(withoutAt);
	const resolved = path.resolve(absolute);
	const brainRoot = path.resolve(BRAIN_DIR);
	if (
		resolved !== brainRoot &&
		!resolved.startsWith(`${brainRoot}${path.sep}`)
	) {
		throw new Error(`Path escapes agentBrain: ${input}`);
	}
	return resolved;
}

export function relativeToBrain(file: string): string {
	return path.relative(BRAIN_DIR, file) || ".";
}
