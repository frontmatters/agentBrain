import { Type } from "typebox";

export function transcriptInfoSchema() {
	return Type.Object({
		url: Type.String({ description: "YouTube video URL" }),
	});
}

export function transcriptDownloadSchema() {
	return Type.Object({
		url: Type.String({ description: "YouTube video URL" }),
		language: Type.Optional(
			Type.String({ description: "Subtitle language code, default en" }),
		),
		outputDir: Type.Optional(
			Type.String({
				description:
					"Directory for .vtt and .txt outputs; defaults to current working directory",
			}),
		),
		outputBase: Type.Optional(
			Type.String({
				description:
					"Base filename without extension; defaults to sanitized video title",
			}),
		),
		saveToBrain: Type.Optional(
			Type.Boolean({
				description: "Also save markdown to agentBrain/local/youtube-knowledge",
			}),
		),
		category: Type.Optional(
			Type.String({
				description:
					"agentBrain category folder when saveToBrain=true, default Other",
			}),
		),
		tags: Type.Optional(
			Type.Array(Type.String({ description: "Tags for agentBrain markdown" })),
		),
		keepVtt: Type.Optional(
			Type.Boolean({
				description: "Keep VTT output in outputDir, default true",
			}),
		),
	});
}
