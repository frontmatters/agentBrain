import type {
	OAuthCredentials,
	OAuthLoginCallbacks,
} from "@earendil-works/pi-ai";

declare const Bun: {
	env: Record<string, string | undefined>;
	spawnSync(args: string[]): { exitCode: number; stdout: Uint8Array };
};

export type ApiKeyLoginOptions = {
	promptMessage: string;
	emptyMessage: string;
};

export function readKeychainSecret(service: string): string {
	try {
		const result = Bun.spawnSync([
			"security",
			"find-generic-password",
			"-a",
			Bun.env.USER ?? "",
			"-s",
			service,
			"-w",
		]);
		if (result.exitCode === 0) {
			return new TextDecoder().decode(result.stdout).trim();
		}
	} catch {
		return "";
	}
	return "";
}

export function createApiKeyOAuth(options: ApiKeyLoginOptions) {
	return {
		async login(callbacks: OAuthLoginCallbacks): Promise<OAuthCredentials> {
			const key = await callbacks.onPrompt({ message: options.promptMessage });
			if (!key?.trim()) throw new Error(options.emptyMessage);
			return { refresh: key.trim(), access: key.trim(), expires: 0 };
		},
		async refreshToken(
			credentials: OAuthCredentials,
		): Promise<OAuthCredentials> {
			return credentials;
		},
		getApiKey(credentials: OAuthCredentials): string {
			return credentials.access;
		},
	};
}

export const OPENAI_COMPAT_NO_REASONING = {
	supportsDeveloperRole: false,
	supportsReasoningEffort: false,
	supportsUsageInStreaming: false,
	maxTokensField: "max_tokens",
} as const;

export const ZERO_COST = {
	input: 0,
	output: 0,
	cacheRead: 0,
	cacheWrite: 0,
} as const;
