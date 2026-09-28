import { readFileSync } from "node:fs";
import { join } from "node:path";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import { toArray } from "./path-utils";
import { ensureGlobalFlags, globToRegExp, safeUserRegExp } from "./regexp";
import type {
	CloakConfig,
	CloakPatternSpec,
	CloakRuleConfig,
	CompiledCloakPattern,
	CompiledCloakRule,
	RuntimeState,
} from "./types";

const DEFAULT_CONFIG_PATH = join(getAgentDir(), "cloak.json");
const DEFAULT_CONFIG: CloakConfig = {
	enabled: true,
	cloakCharacter: "*",
	cloakLength: null,
	tryAllPatterns: true,
	patterns: [],
};

function compilePattern(
	spec: CloakPatternSpec,
	ruleReplace?: string,
): CompiledCloakPattern {
	if (typeof spec === "string") {
		return {
			source: spec,
			regex: safeUserRegExp(spec, "g"),
			replace: ruleReplace,
		};
	}

	return {
		source: spec.pattern,
		regex: safeUserRegExp(spec.pattern, ensureGlobalFlags(spec.flags)),
		replace: spec.replace ?? ruleReplace,
	};
}

function compileRule(rule: CloakRuleConfig): CompiledCloakRule {
	const filePatterns = toArray(rule.filePattern);
	const cloakPatterns = toArray(rule.cloakPattern);
	return {
		filePatterns,
		fileRegexes: filePatterns.map(globToRegExp),
		patterns: cloakPatterns.map((pattern) =>
			compilePattern(pattern, rule.replace),
		),
	};
}

export function loadState(
	configPath: string = DEFAULT_CONFIG_PATH,
): RuntimeState {
	try {
		const config = readConfig(configPath);
		return {
			configPath,
			config,
			rules: (config.patterns ?? []).map(compileRule),
		};
	} catch (error) {
		return loadStateError(configPath, error);
	}
}

function readConfig(configPath: string): CloakConfig {
	const raw = readFileSync(configPath, "utf8");
	const parsed = JSON.parse(raw) as CloakConfig;
	return {
		...DEFAULT_CONFIG,
		...parsed,
		patterns: parsed.patterns ?? [],
	};
}

function loadStateError(configPath: string, error: unknown): RuntimeState {
	return {
		configPath,
		config: DEFAULT_CONFIG,
		rules: [],
		error: isMissingFile(error)
			? `pi-cloak config not found at ${configPath}`
			: `pi-cloak failed to load ${configPath}: ${formatError(error)}`,
	};
}

function isMissingFile(error: unknown): boolean {
	return error instanceof Error && "code" in error && error.code === "ENOENT";
}

function formatError(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}
