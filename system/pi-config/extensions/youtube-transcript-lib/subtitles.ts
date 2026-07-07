import * as fsp from "node:fs/promises";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { cleanVttToText, truncateText } from "../youtube-transcript-utils";
import { downloadSubtitle, findVttFile, listSubs } from "./cli";
import type { SubtitleSource } from "./types";
import type { ProgressUpdate } from "./workflow";

export async function fetchSubtitle(
	pi: ExtensionAPI,
	url: string,
	language: string,
	tempDir: string,
	signal: AbortSignal | undefined,
	progress?: ProgressUpdate,
): Promise<SubtitleSource> {
	progress?.(`Trying manual ${language} subtitles...`);
	const manual = await downloadSubtitle(
		pi,
		url,
		language,
		"manual",
		tempDir,
		signal,
	);
	if (manual.ok) return "manual";
	progress?.(
		`Manual subtitles unavailable; trying auto-generated ${language} subtitles...`,
	);
	const automatic = await downloadSubtitle(
		pi,
		url,
		language,
		"auto",
		tempDir,
		signal,
	);
	if (automatic.ok) return "auto";
	return "manual";
}

export async function readTranscript(
	pi: ExtensionAPI,
	url: string,
	language: string,
	tempDir: string,
	signal: AbortSignal | undefined,
): Promise<string> {
	const vttFile = await findVttFile(tempDir);
	if (!vttFile) await throwNoSubtitles(pi, url, language, signal);
	const vtt = await fsp.readFile(vttFile as string, "utf8");
	const transcript = cleanVttToText(vtt);
	if (!transcript.trim()) {
		throw new Error(
			"Downloaded VTT file did not contain usable transcript text.",
		);
	}
	return transcript;
}

async function throwNoSubtitles(
	pi: ExtensionAPI,
	url: string,
	language: string,
	signal: AbortSignal | undefined,
): Promise<void> {
	const subs = await listSubs(pi, url, signal);
	throw new Error(
		`No ${language} subtitles were downloaded. Available subtitles:\n${truncateText(subs)}\n\nIf no usable subtitles exist, ask the user before downloading audio and using Whisper.`,
	);
}
