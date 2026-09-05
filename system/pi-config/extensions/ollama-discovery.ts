// @ts-nocheck
/**
 * Local Ollama Discovery Provider Extension
 *
 * Dynamically discovers models from a local Ollama daemon and registers them
 * with Pi as the built-in `ollama` provider. This avoids keeping
 * ~/.pi/agent/models.json in sync by hand for local Ollama pulls.
 *
 * Usage:
 *   ollama serve             — ensure Ollama is running
 *   /reload                  — reload Pi extensions and rediscover models
 *   /model                   — switch to an `ollama` model
 *
 * Configuration:
 *   OLLAMA_HOST=http://127.0.0.1:11434  — optional custom Ollama host
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const DEFAULT_OLLAMA_HOST = "http://127.0.0.1:11434";
const DEFAULT_CONTEXT_WINDOW = 128000;
const DEFAULT_MAX_TOKENS = 16384;
const DISCOVERY_TIMEOUT_MS = 2500;

type OllamaTag = {
	name?: string;
	model?: string;
};

type OllamaShow = {
	capabilities?: string[];
	model_info?: Record<string, unknown>;
};

function normalizeHost(host: string | undefined): string {
	return (host || DEFAULT_OLLAMA_HOST).replace(/\/+$/, "");
}

function withTimeout(ms: number): AbortSignal {
	const controller = new AbortController();
	setTimeout(() => controller.abort(), ms).unref?.();
	return controller.signal;
}

async function fetchJson(url: string, init: RequestInit = {}) {
	const response = await fetch(url, {
		...init,
		signal: init.signal ?? withTimeout(DISCOVERY_TIMEOUT_MS),
	});
	if (!response.ok) {
		throw new Error(`${response.status} ${response.statusText}`);
	}
	return response.json();
}

function findContextWindow(
	modelInfo: Record<string, unknown> | undefined,
): number {
	if (!modelInfo) return DEFAULT_CONTEXT_WINDOW;

	const contextEntry = Object.entries(modelInfo).find(([key, value]) => {
		return key.endsWith(".context_length") && typeof value === "number";
	});
	if (typeof contextEntry?.[1] === "number" && contextEntry[1] > 0) {
		return contextEntry[1];
	}

	const direct = modelInfo.context_length;
	if (typeof direct === "number" && direct > 0) return direct;

	return DEFAULT_CONTEXT_WINDOW;
}

function isReasoningModel(modelId: string): boolean {
	const id = modelId.toLowerCase();
	return (
		id.startsWith("qwen3") ||
		id.includes("deepseek-r1") ||
		id.includes("gpt-oss") ||
		id.includes("magistral")
	);
}

function isVisionModel(modelId: string, show: OllamaShow | undefined): boolean {
	const capabilities = show?.capabilities ?? [];
	if (capabilities.includes("vision")) return true;

	const id = modelId.toLowerCase();
	return (
		id.includes("vision") ||
		id.includes("llava") ||
		id.includes("bakllava") ||
		id.includes("moondream") ||
		id.includes("qwen2.5vl") ||
		id.includes("qwen2.5-vl") ||
		id.includes("qwen3-vl")
	);
}

async function getLocalOllamaModels(host: string) {
	const tags = (await fetchJson(`${host}/api/tags`)) as {
		models?: OllamaTag[];
	};
	const names = (tags.models ?? [])
		.map((model) => model.name ?? model.model)
		.filter((name): name is string => Boolean(name));

	const models = [];
	for (const id of names) {
		let show: OllamaShow | undefined;
		try {
			show = (await fetchJson(`${host}/api/show`, {
				method: "POST",
				headers: { "content-type": "application/json" },
				body: JSON.stringify({ model: id }),
			})) as OllamaShow;
		} catch {
			show = undefined;
		}

		models.push({
			id,
			name: id,
			reasoning: isReasoningModel(id),
			input: isVisionModel(id, show) ? ["text", "image"] : ["text"],
			contextWindow: findContextWindow(show?.model_info),
			maxTokens: DEFAULT_MAX_TOKENS,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		});
	}

	return models;
}

export default async function (pi: ExtensionAPI) {
	const host = normalizeHost(process.env.OLLAMA_HOST);

	let models = [];
	try {
		models = await getLocalOllamaModels(host);
	} catch {
		// Ollama is optional. If it is not running, keep startup quiet and leave any
		// static ~/.pi/agent/models.json `ollama` entries untouched.
		return;
	}

	if (models.length === 0) return;

	pi.registerProvider("ollama", {
		name: "Ollama Local",
		baseUrl: `${host}/v1`,
		apiKey: "ollama",
		api: "openai-completions",
		compat: {
			supportsDeveloperRole: false,
			supportsReasoningEffort: false,
			supportsUsageInStreaming: false,
			maxTokensField: "max_tokens",
		},
		models,
	});
}
