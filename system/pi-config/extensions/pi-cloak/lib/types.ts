export type CloakPatternSpec =
	| string
	| {
			pattern: string;
			replace?: string;
			flags?: string;
	  };

export interface CloakRuleConfig {
	filePattern: string | string[];
	cloakPattern: CloakPatternSpec | CloakPatternSpec[];
	replace?: string;
}

export interface CloakConfig {
	enabled?: boolean;
	cloakCharacter?: string;
	cloakLength?: number | null;
	tryAllPatterns?: boolean;
	patterns?: CloakRuleConfig[];
}

export interface CompiledCloakPattern {
	source: string;
	regex: RegExp;
	replace?: string;
}

export interface CompiledCloakRule {
	filePatterns: string[];
	fileRegexes: RegExp[];
	patterns: CompiledCloakPattern[];
}

export interface RuntimeState {
	configPath: string;
	config: CloakConfig;
	rules: CompiledCloakRule[];
	error?: string;
}
