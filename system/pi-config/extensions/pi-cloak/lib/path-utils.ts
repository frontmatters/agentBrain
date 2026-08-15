import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";

export function toArray<T>(value: T | T[] | undefined): T[] {
	if (value === undefined) return [];
	return Array.isArray(value) ? value : [value];
}

export function normalizeSlashes(value: string): string {
	return value.split("\\").join("/");
}

export function expandHome(value: string): string {
	if (value === "~") return homedir();
	if (value.startsWith("~/")) return join(homedir(), value.slice(2));
	return value;
}

export function normalizePath(value: string): string {
	return normalizeSlashes(expandHome(value.trim()));
}

export function stripLeadingAt(value: string): string {
	return value.startsWith("@") ? value.slice(1) : value;
}

export function getPathCandidates(rawPath: string, cwd: string): string[] {
	const cleanPath = normalizePath(stripLeadingAt(rawPath));
	const absolutePath = normalizePath(
		resolve(cwd, expandHome(stripLeadingAt(rawPath))),
	);

	return Array.from(
		new Set([
			cleanPath,
			absolutePath,
			basename(cleanPath),
			basename(absolutePath),
		]),
	);
}
