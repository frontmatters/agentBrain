import type { CloakConfig, CompiledCloakPattern } from "./types";

export function applyPatternsToLine(
	line: string,
	patterns: CompiledCloakPattern[],
	config: CloakConfig,
): { line: string; changed: boolean } {
	let updated = line;
	let changed = false;

	for (const pattern of patterns) {
		const result = applyPattern(updated, pattern, config);
		if (!result.changed) continue;
		updated = result.line;
		changed = true;
		if (!config.tryAllPatterns) break;
	}

	return { line: updated, changed };
}

function applyPattern(
	line: string,
	pattern: CompiledCloakPattern,
	config: CloakConfig,
): { line: string; changed: boolean } {
	let changed = false;
	const updated = line.replace(
		pattern.regex,
		(match: string, ...args: unknown[]) => {
			const replacement = buildMaskedReplacement(
				match,
				extractCaptures(args),
				pattern.replace,
				config.cloakCharacter ?? "*",
				config.cloakLength,
			);
			if (replacement !== match) changed = true;
			return replacement;
		},
	);
	return { line: updated, changed };
}

function extractCaptures(args: unknown[]): string[] {
	return args
		.slice(0, Math.max(0, args.length - 2))
		.map((value) => String(value ?? ""));
}

function buildMaskedReplacement(
	match: string,
	captures: string[],
	replace: string | undefined,
	cloakCharacter: string,
	cloakLength: number | null | undefined,
): string {
	const visible = replace
		? applyReplacementTemplate(replace, match, captures)
		: match.slice(0, 1);
	const targetLength = cloakLength ?? Math.max(match.length, visible.length);
	const truncatedVisible = visible.slice(0, targetLength);
	const maskedLength = Math.max(0, targetLength - truncatedVisible.length);
	return truncatedVisible + repeatToLength(cloakCharacter, maskedLength);
}

function repeatToLength(seed: string, length: number): string {
	if (length <= 0 || !seed) return "";
	const repeatCount = Math.ceil(length / seed.length);
	return seed.repeat(repeatCount).slice(0, length);
}

function applyReplacementTemplate(
	template: string,
	match: string,
	captures: string[],
): string {
	let result = "";
	for (let index = 0; index < template.length; index++) {
		const token = readTemplateToken(template, index, match, captures);
		result += token.value;
		index += token.skip;
	}
	return result;
}

function readTemplateToken(
	template: string,
	index: number,
	match: string,
	captures: string[],
): { value: string; skip: number } {
	const char = template[index] ?? "";
	if (char !== "$") return { value: char, skip: 0 };
	const next = template[index + 1];
	if (!next) return { value: "$", skip: 0 };
	if (next === "$") return { value: "$", skip: 1 };
	if (next === "&") return { value: match, skip: 1 };
	if (/\d/.test(next)) return readBackReference(template, index, captures);
	return { value: `$${next}`, skip: 1 };
}

function readBackReference(
	template: string,
	index: number,
	captures: string[],
): { value: string; skip: number } {
	let end = index + 1;
	while (canConsumeBackrefDigit(template, index, end)) end += 1;
	const groupIndex = Number(template.slice(index + 1, end + 1)) - 1;
	return { value: captures[groupIndex] ?? "", skip: end - index };
}

function canConsumeBackrefDigit(
	template: string,
	index: number,
	end: number,
): boolean {
	const hasNext = end + 1 < template.length;
	const isDigit = /\d/.test(template[end + 1] ?? "");
	const withinBackrefLimit = end - index < 2;
	return hasNext && isDigit && withinBackrefLimit;
}
