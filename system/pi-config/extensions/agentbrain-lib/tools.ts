import * as fsp from "node:fs/promises";
import { BRAIN_DIR, brainPath } from "../brain-paths";
import { normalizeBrainPath, relativeToBrain } from "./paths";
import { collectProjectContext } from "./project";
import { listMarkdownFiles, readLimited } from "./files";
import type { BrainStatusContext } from "./status";

export type BrainReadParams = { paths: string[] };
export type BrainSearchParams = {
	query: string;
	scope?: string;
	maxResults?: number;
};
export type BrainProjectContextParams = { project?: string };

export async function runReadTool(params: BrainReadParams) {
	const sections: string[] = [];
	for (const requested of params.paths) {
		const file = normalizeBrainPath(requested);
		const { text, truncated } = await readLimited(file);
		sections.push(formatReadSection({ file, text, truncated }));
	}
	return {
		content: [{ type: "text" as const, text: sections.join("\n\n---\n\n") }],
		details: { paths: params.paths },
	};
}

function formatReadSection(options: {
	file: string;
	text: string;
	truncated: boolean;
}): string {
	const suffix = options.truncated ? "\n\n[Truncated at 50KB]" : "";
	return `# ${relativeToBrain(options.file)}\n\n${options.text}${suffix}`;
}

export async function runSearchTool(params: BrainSearchParams) {
	const query = params.query.toLowerCase();
	const maxResults = Math.min(Math.max(params.maxResults ?? 40, 1), 200);
	const files = (
		await Promise.all(
			scopeRoots(params.scope).map((root) => listMarkdownFiles(root)),
		)
	).flat();
	const matches = await collectLineMatches(files, query, maxResults);
	return {
		content: [
			{
				type: "text" as const,
				text: matches.length
					? matches.join("\n")
					: `No matches for: ${params.query}`,
			},
		],
		details: { count: matches.length, scope: params.scope ?? "all" },
	};
}

function scopeRoots(scope?: string): string[] {
	switch ((scope ?? "all").toLowerCase()) {
		case "shared":
			return [
				"learnings",
				"system",
				"templates",
				"projects",
				"user-preferences",
			].map((p) => brainPath(p));
		case "local":
			return [brainPath("local")];
		case "projects":
			return [brainPath("local", "projects"), brainPath("projects")];
		default:
			return [BRAIN_DIR];
	}
}

async function collectLineMatches(
	files: string[],
	query: string,
	maxResults: number,
): Promise<string[]> {
	const matches: string[] = [];
	for (const file of files) {
		await collectFileMatches(file, query, maxResults, matches);
		if (matches.length >= maxResults) break;
	}
	return matches;
}

async function collectFileMatches(
	file: string,
	query: string,
	maxResults: number,
	matches: string[],
): Promise<void> {
	const text = await fsp.readFile(file, "utf8");
	const lines = text.split(/\r?\n/);
	for (let index = 0; index < lines.length; index++) {
		const line = lines[index];
		if (!line.toLowerCase().includes(query)) continue;
		matches.push(`${relativeToBrain(file)}:${index + 1}: ${line.trim()}`);
		if (matches.length >= maxResults) break;
	}
}

export async function runProjectContextTool(
	params: BrainProjectContextParams,
	ctx: BrainStatusContext,
) {
	const { projectDir, sections } = await collectProjectContext(
		ctx.cwd,
		params.project,
	);
	if (!projectDir) return missingProjectContextResult();
	return {
		content: [
			{
				type: "text" as const,
				text: `Project: ${relativeToBrain(projectDir)}\n\n${sections.join("\n\n---\n\n")}`,
			},
		],
		details: { projectDir },
	};
}

function missingProjectContextResult() {
	return {
		content: [
			{
				type: "text" as const,
				text: "No matching agentBrain project context found.",
			},
		],
		details: {},
	};
}
