const MAX_TOOL_TEXT_BYTES = 50_000;

export function sanitizeFilePart(
	input: string,
	fallback = "youtube-video",
): string {
	const cleaned = input
		.normalize("NFKD")
		.replace(/[\u0300-\u036f]/g, "")
		.replace(/[\\/:*?"<>|#%{}$!'@+`=]/g, "-")
		.replace(/\s+/g, " ")
		.trim()
		.replace(/\s/g, "-")
		.replace(/-+/g, "-")
		.replace(/^-|-$/g, "")
		.slice(0, 120);
	return cleaned || fallback;
}

export function formatUploadDate(uploadDate?: string): string {
	const hasUploadDate = Boolean(uploadDate);
	const hasExpectedDateShape = /^\d{8}$/.test(uploadDate ?? "");
	if (!hasUploadDate) return new Date().toISOString().slice(0, 10);
	if (!hasExpectedDateShape) return new Date().toISOString().slice(0, 10);
	return `${uploadDate?.slice(0, 4)}-${uploadDate?.slice(4, 6)}-${uploadDate?.slice(6, 8)}`;
}

export function truncateText(text: string): string {
	const buffer = Buffer.from(text, "utf8");
	if (buffer.length <= MAX_TOOL_TEXT_BYTES) return text;
	return `${buffer.subarray(0, MAX_TOOL_TEXT_BYTES).toString("utf8")}\n\n[Truncated at ${MAX_TOOL_TEXT_BYTES} bytes]`;
}

export function cleanVttToText(vtt: string): string {
	const seen = new Set<string>();
	const lines: string[] = [];

	for (const rawLine of vtt.split(/\r?\n/)) {
		let line = rawLine.trim();
		if (!line) continue;
		if (line === "WEBVTT") continue;
		if (line.startsWith("Kind:") || line.startsWith("Language:")) continue;
		if (
			line.startsWith("NOTE") ||
			line.startsWith("STYLE") ||
			line.startsWith("REGION")
		)
			continue;
		if (line.includes("-->")) continue;
		if (/^\d+$/.test(line)) continue;

		line = line
			.replace(/<[^>]+>/g, "")
			.replace(/&amp;/g, "&")
			.replace(/&gt;/g, ">")
			.replace(/&lt;/g, "<")
			.replace(/&quot;/g, '"')
			.replace(/&#39;/g, "'")
			.replace(/\s+/g, " ")
			.trim();

		if (!line || seen.has(line)) continue;
		seen.add(line);
		lines.push(line);
	}

	return lines.join("\n");
}
