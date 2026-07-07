import { normalizePath } from "./path-utils";

const MAX_USER_REGEX_LENGTH = 1_000;
const VALID_REGEX_FLAGS = /^[dgimsuvy]*$/;

export function escapeRegex(value: string): string {
	return value.replace(/[|\\{}()[\]^$+?.]/g, "\\$&");
}

export function globToRegExp(glob: string): RegExp {
	const pattern = globPatternSource(normalizePath(glob));
	return RegExp(`^${pattern}$`);
}

function globPatternSource(normalized: string): string {
	let pattern = "";
	for (let index = 0; index < normalized.length; index++) {
		const token = globToken(normalized, index);
		pattern += token.source;
		index += token.skip;
	}
	return pattern;
}

function globToken(
	value: string,
	index: number,
): { source: string; skip: number } {
	const char = value[index] ?? "";
	const next = value[index + 1];
	const afterNext = value[index + 2];
	if (char === "*" && next === "*" && afterNext === "/") {
		return { source: "(?:.*/)?", skip: 2 };
	}
	if (char === "*" && next === "*") return { source: ".*", skip: 1 };
	if (char === "*") return { source: "[^/]*", skip: 0 };
	if (char === "?") return { source: "[^/]", skip: 0 };
	return { source: escapeRegex(char), skip: 0 };
}

export function ensureGlobalFlags(flags?: string): string {
	const unique = new Set((flags ?? "").split("").filter(Boolean));
	unique.add("g");
	return Array.from(unique).join("");
}

export function safeUserRegExp(pattern: string, flags = "g"): RegExp {
	validateUserRegExp(pattern, flags);
	// Intentional dynamic regexp: pi-cloak is a user-configured redaction engine.
	// The pattern is bounded and flags are allowlisted before compilation.
	return RegExp(pattern, flags);
}

function validateUserRegExp(pattern: string, flags: string): void {
	if (pattern.length > MAX_USER_REGEX_LENGTH) {
		throw new Error(`Cloak regex is too long (${pattern.length} chars)`);
	}
	if (!VALID_REGEX_FLAGS.test(flags)) {
		throw new Error(`Invalid cloak regex flags: ${flags}`);
	}
}
