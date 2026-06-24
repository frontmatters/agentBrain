export type VideoInfo = {
	id?: string;
	title?: string;
	channel?: string;
	uploader?: string;
	upload_date?: string;
	duration?: number;
	webpage_url?: string;
};

export type SubtitleSource = "manual" | "auto";

export type DownloadTranscriptParams = {
	url: string;
	language?: string;
	outputDir?: string;
	outputBase?: string;
	saveToBrain?: boolean;
	category?: string;
	tags?: string[];
	keepVtt?: boolean;
};

export type TranscriptDownloadResult = {
	info: VideoInfo;
	source: SubtitleSource;
	language: string;
	transcript: string;
	txtPath: string;
	vttPath?: string;
	brainPath?: string;
};
