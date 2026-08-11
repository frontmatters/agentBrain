import * as fsp from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getVideoInfo } from "./cli";
import { writeAgentBrainMarkdown } from "./markdown";
import { writeTranscriptOutputs } from "./outputs";
import { fetchSubtitle, readTranscript } from "./subtitles";
import type {
	DownloadTranscriptParams,
	TranscriptDownloadResult,
} from "./types";

export type ProgressUpdate = (text: string) => void;

export async function downloadTranscript(
	pi: ExtensionAPI,
	params: DownloadTranscriptParams,
	ctx: { cwd: string },
	signal: AbortSignal | undefined,
	progress?: ProgressUpdate,
): Promise<TranscriptDownloadResult> {
	progress?.("Reading video metadata...");
	const info = await getVideoInfo(pi, params.url, signal);
	const tempDir = await fsp.mkdtemp(
		path.join(os.tmpdir(), "pi-youtube-transcript-"),
	);
	try {
		const language = params.language || "en";
		const source = await fetchSubtitle(
			pi,
			params.url,
			language,
			tempDir,
			signal,
			progress,
		);
		const transcript = await readTranscript(
			pi,
			params.url,
			language,
			tempDir,
			signal,
		);
		const output = await writeTranscriptOutputs(
			ctx.cwd,
			params,
			info,
			transcript,
			tempDir,
		);
		const brainPath = await maybeSaveToBrain(
			params,
			info,
			transcript,
			language,
			source,
		);
		return { info, source, language, transcript, ...output, brainPath };
	} finally {
		await fsp.rm(tempDir, { recursive: true, force: true });
	}
}

async function maybeSaveToBrain(
	params: DownloadTranscriptParams,
	info: TranscriptDownloadResult["info"],
	transcript: string,
	language: string,
	source: TranscriptDownloadResult["source"],
): Promise<string | undefined> {
	if (!params.saveToBrain) return undefined;
	return await writeAgentBrainMarkdown({
		info,
		transcript,
		category: params.category || "Other",
		tags: params.tags || [],
		language,
		source,
	});
}
