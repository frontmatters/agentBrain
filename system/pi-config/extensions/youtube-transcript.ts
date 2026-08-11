import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	ensureYtDlp,
	getVideoInfo,
	listSubs,
} from "./youtube-transcript-lib/cli";
import { infoText, resultText } from "./youtube-transcript-lib/format";
import {
	transcriptDownloadSchema,
	transcriptInfoSchema,
} from "./youtube-transcript-lib/schema";
import { downloadTranscript } from "./youtube-transcript-lib/workflow";

function registerInfoTool(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "youtube_transcript_info",
		label: "YouTube Transcript Info",
		description:
			"Inspect a YouTube video and list available subtitles/captions using yt-dlp. Requires yt-dlp installed.",
		promptSnippet:
			"Inspect YouTube video metadata and available subtitles/captions",
		promptGuidelines: [
			"Use youtube_transcript_info before downloading YouTube transcripts when the user provides a YouTube URL.",
		],
		parameters: transcriptInfoSchema(),
		async execute(_toolCallId, params, signal) {
			await ensureYtDlp(pi, signal);
			const [info, subs] = await Promise.all([
				getVideoInfo(pi, params.url, signal),
				listSubs(pi, params.url, signal),
			]);
			return {
				content: [{ type: "text" as const, text: infoText(info, subs) }],
				details: { info, subtitles: subs },
			};
		},
	});
}

function registerDownloadTool(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "youtube_transcript_download",
		label: "YouTube Transcript Download",
		description:
			"Download a YouTube transcript via yt-dlp subtitles, convert VTT to deduplicated plain text, and optionally save markdown to agentBrain/local/youtube-digest. Does not download audio or run Whisper.",
		promptSnippet:
			"Download YouTube subtitles and convert them to clean transcript text",
		promptGuidelines: [
			"Use youtube_transcript_download for YouTube transcript requests before falling back to manual bash commands.",
			"youtube_transcript_download does not use Whisper; if no subtitles exist, ask the user before audio download/transcription.",
		],
		parameters: transcriptDownloadSchema(),
		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			await ensureYtDlp(pi, signal);
			const result = await downloadTranscript(pi, params, ctx, signal, (text) =>
				onUpdate?.({ content: [{ type: "text", text }], details: {} }),
			);
			return {
				content: [{ type: "text" as const, text: resultText(result) }],
				details: result,
			};
		},
	});
}

export default function youtubeTranscriptExtension(pi: ExtensionAPI): void {
	registerInfoTool(pi);
	registerDownloadTool(pi);
	pi.registerCommand("youtube-transcript-tools", {
		description: "Show available YouTube transcript extension tools",
		handler: async (_args, ctx) => {
			ctx.ui.notify(
				"Tools: youtube_transcript_info, youtube_transcript_download",
				"info",
			);
		},
	});
}
