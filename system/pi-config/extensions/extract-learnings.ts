import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { convertToLlm } from "@earendil-works/pi-coding-agent";
import { runBounded } from "./extract-learnings-lib/bounded";
import { doExtraction } from "./extract-learnings-lib/extractor";
import { isIncognito } from "./brain-paths";

const HARD_TIMEOUT_MS = 20_000;

type LlmMessages = ReturnType<typeof convertToLlm>;
type SessionEntry = { type?: string; message?: unknown };

export default function extractLearningsExtension(pi: ExtensionAPI): void {
	let lastCompactionMessages: LlmMessages = [];
	let lastSessionFile: string | undefined;

	pi.on("session_start", async (_event, ctx) => {
		lastSessionFile = ctx.sessionManager.getSessionFile() ?? undefined;
	});

	pi.on("session_before_compact", async (event, ctx) => {
		if (isIncognito()) return; // read-only session: persist no learnings
		const { messagesToSummarize, tokensBefore } = event.preparation;
		const messages = convertToLlm(messagesToSummarize);
		lastCompactionMessages = messages;
		await runBounded(HARD_TIMEOUT_MS, (signal) =>
			doExtraction(messages, lastSessionFile, tokensBefore, signal, ctx),
		);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		if (isIncognito()) return; // read-only session: persist no learnings
		if (lastCompactionMessages.length >= 4) return;
		const messages = shutdownMessages(ctx.sessionManager.getEntries());
		if (messages.length < 4) return;
		await runBounded(HARD_TIMEOUT_MS, (signal) =>
			doExtraction(
				messages,
				lastSessionFile,
				messages.length * 200,
				signal,
				ctx,
			),
		);
	});
}

function shutdownMessages(entries: unknown[]): LlmMessages {
	const messageEntries = (entries as SessionEntry[])
		.filter((entry) => entry.type === "message" && entry.message)
		.map((entry) => entry.message);
	return convertToLlm(messageEntries as Parameters<typeof convertToLlm>[0]);
}
