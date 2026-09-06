import * as fsp from "node:fs/promises";
import * as path from "node:path";
import { sanitizeFilePart } from "../youtube-transcript-utils";
import { findVttFile } from "./cli";
import type { DownloadTranscriptParams } from "./types";

export async function writeTranscriptOutputs(
	cwd: string,
	params: DownloadTranscriptParams,
	info: { title?: string; id?: string },
	transcript: string,
	tempDir: string,
): Promise<{ txtPath: string; vttPath?: string }> {
	const vtt = await readOptionalVtt(tempDir);
	const outDir = path.resolve(cwd, params.outputDir || ".");
	await fsp.mkdir(outDir, { recursive: true });
	const base = sanitizeFilePart(
		params.outputBase || info.title || info.id || "youtube-transcript",
	);
	const txtPath = path.join(outDir, `${base}.txt`);
	const vttPath = path.join(outDir, `${base}.vtt`);
	await fsp.writeFile(txtPath, `${transcript}\n`, "utf8");
	if (params.keepVtt !== false && vtt !== undefined) {
		await fsp.writeFile(vttPath, vtt, "utf8");
	}
	return { txtPath, vttPath: params.keepVtt !== false ? vttPath : undefined };
}

async function readOptionalVtt(tempDir: string): Promise<string | undefined> {
	const vttFile = await findVttFile(tempDir);
	return vttFile ? fsp.readFile(vttFile, "utf8") : undefined;
}
