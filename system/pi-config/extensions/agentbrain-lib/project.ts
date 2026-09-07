import * as fs from "node:fs";
import * as path from "node:path";
import { brainPath } from "../brain-paths";
import { MAX_FILE_BYTES, MAX_PROJECT_BYTES, PROJECT_FILES } from "./constants";
import { exists, readLimited } from "./files";
import { relativeToBrain } from "./paths";

// pi-lens-ignore: ts-path-traversal — cwd is Pi's working directory, not user input
export function findProjectRoot(cwd: string): string {
	let current = path.resolve(cwd);
	while (true) {
		if (fs.existsSync(path.join(current, ".git"))) return current;
		const parent = path.dirname(current);
		if (parent === current) return path.resolve(cwd);
		current = parent;
	}
}

export function projectNameCandidates(
	cwd: string,
	explicit?: string,
): string[] {
	const candidates = new Set<string>();
	if (explicit?.trim()) candidates.add(explicit.trim());
	const root = findProjectRoot(cwd);
	candidates.add(path.basename(root));
	candidates.add(path.basename(cwd));
	if (isPiAgentPath(cwd)) candidates.add("pi-agent");
	return [...candidates].filter(Boolean);
}

function isPiAgentPath(cwd: string): boolean {
	return (
		cwd.includes(`${path.sep}.pi${path.sep}agent`) ||
		cwd.endsWith(`${path.sep}.pi${path.sep}agent`)
	);
}

// pi-lens-ignore: ts-path-traversal — paths built via brainPath(), validated against vault root
export async function detectProjectDir(
	cwd: string,
	explicit?: string,
): Promise<string | undefined> {
	for (const name of projectNameCandidates(cwd, explicit)) {
		const candidate = brainPath("local", "projects", name);
		if (await exists(path.join(candidate, "index.md"))) return candidate;
	}
	return undefined;
}

export async function collectProjectContext(
	cwd: string,
	explicit?: string,
): Promise<{ projectDir?: string; sections: string[] }> {
	const projectDir = await detectProjectDir(cwd, explicit);
	if (!projectDir) return { sections: [] };

	const sections: string[] = [];
	let used = 0;
	for (const fileName of PROJECT_FILES) {
		const section = await readProjectFileSection(projectDir, fileName, used);
		if (!section) continue;
		sections.push(section.text);
		used += section.bytes;
		if (used >= MAX_PROJECT_BYTES) break;
	}
	return { projectDir, sections };
}

async function readProjectFileSection(
	projectDir: string,
	fileName: string,
	usedBytes: number,
): Promise<{ text: string; bytes: number } | undefined> {
	const file = path.join(projectDir, fileName);
	if (!(await exists(file))) return undefined;
	const remaining = Math.max(0, MAX_PROJECT_BYTES - usedBytes);
	if (remaining === 0) return undefined;
	const { text, truncated } = await readLimited(
		file,
		Math.min(MAX_FILE_BYTES, remaining),
	);
	return {
		text: formatProjectSection({ file, text, truncated }),
		bytes: Buffer.byteLength(text),
	};
}

function formatProjectSection(options: {
	file: string;
	text: string;
	truncated: boolean;
}): string {
	const suffix = options.truncated ? "\n\n[Truncated]" : "";
	return `## ${relativeToBrain(options.file)}\n\n${options.text}${suffix}`;
}
