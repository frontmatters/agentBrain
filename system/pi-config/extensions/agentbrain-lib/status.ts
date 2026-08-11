import * as fsp from "node:fs/promises";
import * as path from "node:path";
import { BRAIN_DIR, brainPath } from "../brain-paths";
import { CORE_FILES } from "./constants";
import { exists, listMarkdownFiles } from "./files";
import { detectProjectDir, findProjectRoot } from "./project";
import { relativeToBrain } from "./paths";

export type BrainStatusContext = { cwd: string };
export type BrainEventContext = {
	cwd: string;
	ui: { setStatus: (id: string, text: string) => void };
};

export async function handleSessionStart(
	ctx: BrainEventContext,
): Promise<void> {
	const project = await detectProjectDir(ctx.cwd);
	if (project) {
		ctx.ui.setStatus("agentBrain", `brain: project: ${path.basename(project)}`);
		return;
	}
	const line = await homeStatusLine();
	if (line) ctx.ui.setStatus("agentBrain", line);
}

export async function runStatusTool(ctx: BrainStatusContext) {
	const projectDir = await detectProjectDir(ctx.cwd);
	const placeholders = await hasPlaceholderPreferences();
	return {
		content: [
			{
				type: "text" as const,
				text: statusText({ ctx, projectDir, placeholders }),
			},
		],
		details: { projectDir, placeholders },
	};
}

function statusText(options: {
	ctx: BrainStatusContext;
	projectDir: string | undefined;
	placeholders: boolean;
}): string {
	return [
		`agentBrain: ${BRAIN_DIR}`,
		`cwd: ${options.ctx.cwd}`,
		`projectRoot: ${findProjectRoot(options.ctx.cwd)}`,
		`detectedProject: ${options.projectDir ? relativeToBrain(options.projectDir) : "none"}`,
		`userPreferencesPersonalized: ${options.placeholders ? "no - run /skill:onboard" : "yes"}`,
		"",
		"Core files:",
		...CORE_FILES.map((f) => `- ${f}`),
	].join("\n");
}

async function hasPlaceholderPreferences(): Promise<boolean> {
	const localPrefDir = brainPath("local", "preferences");
	const sharedPrefDir = brainPath("user-preferences");
	const prefDir = (await exists(localPrefDir)) ? localPrefDir : sharedPrefDir;
	const files = await listMarkdownFiles(prefDir);
	if (files.length === 0) return true;
	for (const file of files) {
		const text = await fsp.readFile(file, "utf8");
		if (isPlaceholderPreference(text)) return true;
	}
	return false;
}

function isPlaceholderPreference(text: string): boolean {
	return (
		text.includes("This is an example file") || text.includes("<!-- Example:")
	);
}

type HomeStatusMode = "overview" | "off" | "ready";

function homeStatusMode(): HomeStatusMode {
	const v = (process.env.AGENTBRAIN_HOME_STATUS ?? "overview").toLowerCase();
	return v === "off" || v === "ready" ? v : "overview";
}

async function homeStatusLine(): Promise<string | undefined> {
	const mode = homeStatusMode();
	if (mode === "off") return undefined;
	if (mode === "ready") return "brain: ready";

	try {
		const projects = await listProjectsWithMtime();
		return formatHomeProjectSummary(projects);
	} catch {
		return "brain: ready";
	}
}

async function listProjectsWithMtime(): Promise<
	{ name: string; mtimeMs: number }[]
> {
	const projectsDir = brainPath("local", "projects");
	const entries = await fsp.readdir(projectsDir, { withFileTypes: true });
	const found: { name: string; mtimeMs: number }[] = [];
	for (const entry of entries) {
		if (!entry.isDirectory()) continue;
		const project = await projectMtime(projectsDir, entry.name);
		if (project) found.push(project);
	}
	return found;
}

async function projectMtime(
	projectsDir: string,
	name: string,
): Promise<{ name: string; mtimeMs: number } | undefined> {
	try {
		const st = await fsp.stat(path.join(projectsDir, name, "index.md"));
		return { name, mtimeMs: st.mtimeMs };
	} catch {
		return undefined;
	}
}

function formatHomeProjectSummary(
	projects: { name: string; mtimeMs: number }[],
): string {
	if (projects.length === 0) return "brain: ready (no project notes yet)";
	projects.sort((a, b) => b.mtimeMs - a.mtimeMs);
	const recent = projects
		.slice(0, 3)
		.map((p) => p.name)
		.join(", ");
	const n = projects.length;
	return `brain: ${n} project${n === 1 ? "" : "s"} · recent: ${recent}`;
}
