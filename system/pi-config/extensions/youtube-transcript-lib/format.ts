import { formatUploadDate, truncateText } from "../youtube-transcript-utils";

export function infoText(
	info: {
		title?: string;
		id?: string;
		channel?: string;
		uploader?: string;
		upload_date?: string;
		duration?: number;
	},
	subs: string,
): string {
	return [
		`Title: ${info.title || "Unknown"}`,
		`Video ID: ${info.id || "Unknown"}`,
		`Channel: ${info.channel || info.uploader || "Unknown"}`,
		`Upload date: ${formatUploadDate(info.upload_date)}`,
		`Duration: ${durationText(info.duration)}`,
		"",
		"Available subtitles:",
		truncateText(subs),
	].join("\n");
}

export function resultText(result: {
	info: { title?: string };
	language: string;
	source: string;
	txtPath: string;
	vttPath?: string;
	brainPath?: string;
	transcript: string;
}): string {
	return [
		`Downloaded transcript: ${result.info.title || result.txtPath}`,
		`Source: ${result.source} subtitles (${result.language})`,
		`Text: ${result.txtPath}`,
		result.vttPath ? `VTT: ${result.vttPath}` : undefined,
		result.brainPath ? `agentBrain: ${result.brainPath}` : undefined,
		"",
		"Preview:",
		truncateText(result.transcript),
	]
		.filter(Boolean)
		.join("\n");
}

function durationText(duration: unknown): string {
	return typeof duration === "number"
		? `${Math.round(duration / 60)} min`
		: "Unknown";
}
