// pi-ai >=0.80 moved the api-dispatch complete() to the compat entrypoint
// (kept unchanged there until the ModelManager migration; see compat.d.ts).
import { complete } from "@earendil-works/pi-ai/compat";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { serializeConversation } from "@earendil-works/pi-coding-agent";
import { extractionPrompt } from "./prompt";
import { getSessionId, saveExtraction } from "./storage";

type ExtensionContext = Parameters<Parameters<ExtensionAPI["on"]>[1]>[1];
type LlmMessages = Parameters<typeof serializeConversation>[0];

export async function doExtraction(
	messages: LlmMessages,
	sessionFile: string | undefined,
	tokensBefore: number,
	signal: AbortSignal,
	ctx: ExtensionContext,
): Promise<void> {
	if (!shouldExtract(messages.length, tokensBefore)) return;
	ctx.ui.setStatus("extract-learnings", "🧠 Extracting learnings...");
	try {
		const extraction = await extractLearnings(
			serializeConversation(messages),
			signal,
			ctx,
		);
		if (!isUsefulExtraction(extraction, signal)) return;
		const filePath = await saveExtraction(
			getSessionId(sessionFile),
			extraction as string,
		);
		ctx.ui.notify(successMessage(filePath), "info");
	} catch (error) {
		ctx.ui.notify(`extract-learnings: ${errorText(error)}`, "warning");
	} finally {
		ctx.ui.setStatus("extract-learnings", "");
	}
}

function shouldExtract(messageCount: number, tokensBefore: number): boolean {
	return messageCount >= 4 && tokensBefore >= 500;
}

async function extractLearnings(
	conversationText: string,
	signal: AbortSignal,
	ctx: ExtensionContext,
): Promise<string | null> {
	const model = ctx.model;
	if (!model) return null;
	const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
	const hasUsableAuth = auth.ok && Boolean(auth.apiKey);
	if (!hasUsableAuth) return null;
	const response = await complete(
		model,
		{
			messages: [
				{
					role: "user",
					content: [{ type: "text", text: extractionPrompt(conversationText) }],
					timestamp: Date.now(),
				},
			],
		},
		{ apiKey: auth.apiKey, headers: auth.headers, maxTokens: 2000, signal },
	);
	return responseText(response.content);
}

function responseText(
	content: Array<{ type: string; text?: string }>,
): string | null {
	return (
		content
			.filter((c): c is { type: "text"; text: string } => c.type === "text")
			.map((c) => c.text)
			.join("\n")
			.trim() || null
	);
}

function isUsefulExtraction(
	extraction: string | null,
	signal: AbortSignal,
): boolean {
	if (!extraction) return false;
	if (extraction === "NOTHING_TO_EXTRACT") return false;
	return !signal.aborted;
}

function successMessage(filePath: string): string {
	const fileName = filePath.split(/[\\/]/).pop() ?? filePath;
	return `🧠 Learnings extracted → local/learnings/extracted/${fileName}\nReview and promote to learnings/ if useful.`;
}

function errorText(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}
