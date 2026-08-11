import { getPathCandidates } from "./path-utils";
import { applyPatternsToLine } from "./replacement";
import type { CompiledCloakRule, RuntimeState } from "./types";

function ruleMatchesPath(
	rule: CompiledCloakRule,
	rawPath: string,
	cwd: string,
): boolean {
	const candidates = getPathCandidates(rawPath, cwd);
	return candidates.some((candidate) =>
		rule.fileRegexes.some((regex) => regex.test(candidate)),
	);
}

export function cloakText(
	rawText: string,
	rawPath: string,
	cwd: string,
	state: RuntimeState,
): string {
	if (!state.config.enabled) return rawText;
	const matchingRules = state.rules.filter((rule) =>
		ruleMatchesPath(rule, rawPath, cwd),
	);
	if (matchingRules.length === 0) return rawText;
	return cloakMatchingLines(rawText, matchingRules, state);
}

function cloakMatchingLines(
	rawText: string,
	matchingRules: CompiledCloakRule[],
	state: RuntimeState,
): string {
	const newline = rawText.includes("\r\n") ? "\r\n" : "\n";
	let changed = false;
	const cloakedLines = rawText.split(/\r?\n/).map((line) => {
		const result = cloakLine(line, matchingRules, state);
		if (result.changed) changed = true;
		return result.line;
	});
	return changed ? cloakedLines.join(newline) : rawText;
}

function cloakLine(
	line: string,
	matchingRules: CompiledCloakRule[],
	state: RuntimeState,
): { line: string; changed: boolean } {
	let updated = line;
	let changed = false;
	for (const rule of matchingRules) {
		const result = applyPatternsToLine(updated, rule.patterns, state.config);
		if (!result.changed) continue;
		updated = result.line;
		changed = true;
	}
	return { line: updated, changed };
}
