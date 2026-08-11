import * as fsp from "node:fs/promises";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { SubtitleSource, VideoInfo } from "./types";

export async function ensureYtDlp(
	pi: ExtensionAPI,
	signal?: AbortSignal,
): Promise<void> {
	const result = await pi.exec("bash", ["-lc", "command -v yt-dlp"], {
		signal,
		timeout: 10_000,
	});
	if (result.code !== 0) {
		throw new Error(
			"yt-dlp is not installed. Install it with `brew install yt-dlp` on macOS, then try again.",
		);
	}
}

export async function getVideoInfo(
	pi: ExtensionAPI,
	url: string,
	signal?: AbortSignal,
): Promise<VideoInfo> {
	const result = await pi.exec(
		"yt-dlp",
		["--dump-single-json", "--skip-download", url],
		{ signal, timeout: 30_000 },
	);
	if (result.code !== 0) throw new Error(commandOutput(result));
	return JSON.parse(result.stdout) as VideoInfo;
}

export async function listSubs(
	pi: ExtensionAPI,
	url: string,
	signal?: AbortSignal,
): Promise<string> {
	const result = await pi.exec("yt-dlp", ["--list-subs", url], {
		signal,
		timeout: 30_000,
	});
	if (result.code !== 0)
		return result.stderr || result.stdout || "No subtitle listing available.";
	return result.stdout;
}

export async function findVttFile(dir: string): Promise<string | undefined> {
	const entries = await fsp.readdir(dir);
	const vtts = entries.filter((entry) => entry.endsWith(".vtt")).sort();
	return vtts[0] ? path.join(dir, vtts[0]) : undefined;
}

export async function downloadSubtitle(
	pi: ExtensionAPI,
	url: string,
	language: string,
	mode: SubtitleSource,
	dir: string,
	signal?: AbortSignal,
): Promise<{ ok: boolean; output: string }> {
	const result = await pi.exec(
		"yt-dlp",
		subtitleArgs(url, language, mode, dir),
		{
			signal,
			timeout: 120_000,
		},
	);
	const vtt = await findVttFile(dir);
	return {
		ok: result.code === 0 && Boolean(vtt),
		output: `${result.stdout}\n${result.stderr}`.trim(),
	};
}

function subtitleArgs(
	url: string,
	language: string,
	mode: SubtitleSource,
	dir: string,
): string[] {
	return [
		mode === "manual" ? "--write-sub" : "--write-auto-sub",
		"--skip-download",
		"--sub-format",
		"vtt",
		"--sub-langs",
		language,
		"--output",
		path.join(dir, "transcript.%(ext)s"),
		url,
	];
}

function commandOutput(result: { stdout?: string; stderr?: string }): string {
	return result.stderr || result.stdout || "Failed to read YouTube metadata";
}
