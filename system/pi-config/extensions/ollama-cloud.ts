// @ts-nocheck
/**
 * Ollama Cloud Provider Extension
 *
 * Adds Ollama Cloud models to Pi with a first-class /login flow.
 * Authentication: Ollama API key stored through Pi credentials.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	createApiKeyOAuth,
	OPENAI_COMPAT_NO_REASONING,
	readKeychainSecret,
	ZERO_COST,
} from "./provider-lib/provider-utils";

const BASE_URL = "https://ollama.com/v1";
const oauth = createApiKeyOAuth({
	promptMessage:
		"Paste your Ollama API key for Ollama Cloud.\nCreate/manage keys at https://ollama.com/settings/keys:",
	emptyMessage: "No Ollama API key provided.",
});

function cloudModel(id: string, name: string) {
	return {
		id,
		name,
		reasoning: true,
		input: ["text"],
		contextWindow: 128000,
		maxTokens: 8192,
		cost: ZERO_COST,
		compat: OPENAI_COMPAT_NO_REASONING,
	};
}

export default function ollamaCloudExtension(pi: ExtensionAPI): void {
	const keychainKey = readKeychainSecret("OLLAMA_API_KEY");
	pi.registerProvider("ollama-cloud", {
		name: "Ollama Cloud",
		baseUrl: BASE_URL,
		apiKey: keychainKey || "$OLLAMA_API_KEY",
		api: "openai-completions",
		compat: OPENAI_COMPAT_NO_REASONING,
		models: [
			cloudModel("gpt-oss:120b-cloud", "GPT-OSS 120B (Ollama Cloud)"),
			cloudModel("gpt-oss:20b-cloud", "GPT-OSS 20B (Ollama Cloud, fast)"),
		],
		oauth: { name: "Ollama Cloud", ...oauth },
	});
}
