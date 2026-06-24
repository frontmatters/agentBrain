import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { cloakText } from "./lib/cloak";
import { loadState } from "./lib/config";

export { cloakText } from "./lib/cloak";
export { loadState } from "./lib/config";

export default function piCloakExtension(pi: ExtensionAPI): void {
	let state = loadState();

	const reloadConfig = () => {
		state = loadState();
	};

	pi.on("session_start", (_event, ctx) => {
		reloadConfig();
		if (state.error && ctx.hasUI) ctx.ui.notify(state.error, "warning");
	});

	pi.registerCommand("cloak-status", {
		description: "Show pi-cloak config status",
		handler: async (_args, ctx) => {
			await Promise.resolve();
			reloadConfig();
			ctx.ui.notify(statusSummary(state), state.error ? "warning" : "info");
		},
	});

	pi.on("tool_result" as any, (event: any, ctx: any) => {
		if (event.toolName !== "read") return undefined;
		if (!state.config.enabled) return undefined;
		const rawPath =
			typeof event.input?.path === "string" ? event.input.path : "";
		if (!rawPath) return undefined;

		const result = cloakTextParts(event.content, rawPath, ctx.cwd, state);
		return result.changed ? { content: result.content } : undefined;
	});
}

function statusSummary(state: ReturnType<typeof loadState>): string {
	if (state.error) return `${state.error}\npatterns: ${state.rules.length}`;
	return `pi-cloak enabled=${state.config.enabled !== false} patterns=${state.rules.length} config=${state.configPath}`;
}

function cloakTextParts(
	content: any[],
	rawPath: string,
	cwd: string,
	state: ReturnType<typeof loadState>,
): { content: any[]; changed: boolean } {
	let changed = false;
	const cloakedContent = content.map((part) => {
		if (part.type !== "text" || typeof part.text !== "string") return part;
		const text = cloakText(part.text, rawPath, cwd, state);
		if (text === part.text) return part;
		changed = true;
		return { ...part, text };
	});
	return { content: cloakedContent, changed };
}
