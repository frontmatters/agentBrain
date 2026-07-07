import * as fsp from "node:fs/promises";
import * as path from "node:path";
import { brainPath } from "../brain-paths";
import {
	formatUploadDate,
	sanitizeFilePart,
} from "../youtube-transcript-utils";
import type { SubtitleSource, VideoInfo } from "./types";

const YOUTUBE_KNOWLEDGE_DIR = brainPath("local", "youtube-digest");

type MarkdownOptions = {
	info: VideoInfo;
	transcript: string;
	category: string;
	tags: string[];
	language: string;
	source: SubtitleSource;
};

export async function writeAgentBrainMarkdown(
	options: MarkdownOptions,
): Promise<string> {
	const target = markdownTarget(options.info, options.category);
	await fsp.mkdir(target.dir, { recursive: true });
	await fsp.writeFile(target.file, markdownBody(options, target), "utf8");
	return target.file;
}

function markdownTarget(info: VideoInfo, category: string) {
	const safeCategory = sanitizeFilePart(category || "Other", "Other");
	const channelName = info.channel || info.uploader || "Unknown Channel";
	const safeChannel = sanitizeFilePart(channelName, "Unknown-Channel");
	const date = formatUploadDate(info.upload_date);
	const year = date.slice(0, 4);
	const dir = path.join(YOUTUBE_KNOWLEDGE_DIR, safeCategory, safeChannel, year);
	const title = info.title || info.id || "YouTube Video";
	const id = info.id || "unknown-id";
	const filename = `${date}-${sanitizeFilePart(title)}-${sanitizeFilePart(id)}.md`;
	return {
		dir,
		file: path.join(dir, filename),
		safeCategory,
		safeChannel,
		channelName,
		date,
	};
}

function markdownBody(
	{ info, transcript, tags, language, source }: MarkdownOptions,
	target: ReturnType<typeof markdownTarget>,
): string {
	const title = info.title || info.id || "YouTube Video";
	const id = info.id || "unknown-id";
	const tagText = tags.length ? tags.join(", ") : "add-tags-here";
	const durationMin = durationMinutes(info.duration);
	const url =
		info.webpage_url ||
		(info.id ? `https://www.youtube.com/watch?v=${info.id}` : "");
	return `# ${title}\n\n## Metadata\n- **Channel**: ${target.channelName}\n- **Channel Slug**: ${target.safeChannel}\n- **Category**: ${target.safeCategory}\n- **Tags**: [${tagText}]\n- **Duration**: ${durationMin ? `${durationMin} min` : "Unknown"}\n- **Upload Date**: ${target.date}\n- **URL**: ${url}\n- **Video ID**: ${id}\n- **Transcript Source**: ${source} subtitles\n- **Language**: ${language}\n- **Synced**: ${new Date().toISOString().slice(0, 16).replace("T", " ")}\n\n## Samenvatting\n> Vul deze samenvatting aan bij review.\n\n## Transcript\n\n${transcript}\n\n## Key Takeaways\n- Aan te vullen bij review.\n\n## Related\n- [[youtube-digest]]\n- [[${target.safeCategory}]]\n`;
}

function durationMinutes(duration: unknown): number | undefined {
	return typeof duration === "number" ? Math.round(duration / 60) : undefined;
}
