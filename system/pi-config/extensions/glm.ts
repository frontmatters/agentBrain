// @ts-nocheck
/**
 * z.ai GLM Coding Plan Provider Extension
 *
 * Adds GLM coding-plan models to Pi with a first-class /login flow.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	createApiKeyOAuth,
	OPENAI_COMPAT_NO_REASONING,
	readKeychainSecret,
	ZERO_COST,
} from "./provider-lib/provider-utils";

const BASE_URL = "https://api.z.ai/api/coding/paas/v4";
const oauth = createApiKeyOAuth({
	promptMessage:
		"Paste your z.ai (GLM Coding Plan) API key.\nGet one at https://z.ai/manage → API Keys:",
	emptyMessage: "No API key provided.",
});

function glmModel(
	id: string,
	name: string,
	contextWindow: number,
	requiresThinkingAsText = true,
) {
	return {
		id,
		name,
		reasoning: true,
		input: ["text"],
		contextWindow,
		maxTokens: 8192,
		cost: ZERO_COST,
		compat: {
			...OPENAI_COMPAT_NO_REASONING,
			requiresThinkingAsText,
		},
	};
}

export default function glmExtension(pi: ExtensionAPI): void {
	const keychainKey = readKeychainSecret("GLM_API_KEY");
	pi.registerProvider("glm", {
		name: "z.ai (GLM Coding Plan)",
		baseUrl: BASE_URL,
		apiKey: keychainKey || "$GLM_API_KEY",
		api: "openai-completions",
		authHeader: false,
		compat: OPENAI_COMPAT_NO_REASONING,
		models: [
			glmModel("glm-4.6", "GLM-4.6 (Coding Plan flagship)", 200000),
			glmModel("glm-4.5", "GLM-4.5 (Coding Plan)", 128000),
			glmModel("glm-4.5-air", "GLM-4.5 Air (Coding Plan, fast)", 128000),
		],
		oauth: { name: "z.ai (GLM Coding Plan)", ...oauth },
	});
}
