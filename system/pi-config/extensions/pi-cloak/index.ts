import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { ImageContent, TextContent } from "@earendil-works/pi-ai";
import { cloakText } from "./lib/cloak";
import { loadState } from "./lib/config";
import { knownSecretValues, redactKnownSecrets } from "./lib/env-secrets";
import { redactSecretShapes } from "./lib/secret-shapes";

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

	pi.on("tool_result", (event, ctx) => {
		if (event.toolName === "bash") return redactBashSecrets(event.content);
		if (event.toolName !== "read") return undefined;
		if (!state.config.enabled) return undefined;
		const rawPath =
			typeof event.input.path === "string" ? event.input.path : "";
		if (!rawPath) return undefined;

		const result = cloakTextParts(event.content, rawPath, ctx.cwd, state);
		return result.changed ? { content: result.content } : undefined;
	});
}

// Always-on safety net for `bash` tool output: unlike the `read` hook, this is
// NOT gated by cloak.json's `enabled` flag or file-glob rules — it's a
// safety net, not an optional user preference. Two independent layers:
//
// 1. Exact-match against Pi's own process.env for secret-ish keys
//    (env-secrets.ts). IMPORTANT LIMITATION: a `bash` tool call runs in a
//    child process — anything `export`-ed inside it is invisible to Pi's
//    own process.env once the call returns (env only flows parent->child,
//    never child->parent). So this layer only catches secrets that were
//    ALREADY part of Pi's host environment before the call (e.g. exported
//    in the shell that launched Pi). Verified empirically it does NOT catch
//    a credential-helper function fetching+printing a fresh secret bare
//    inside the bash subprocess — that case needs layer 2.
// 2. Content-shape detection (secret-shapes.ts): recognizes secret shapes
//    directly in the output text regardless of which process produced it
//    (bare long-token lines, known token prefixes). This is what actually
//    catches the credential-helper-invoked-bare case.
function redactBashSecrets(
	content: (TextContent | ImageContent)[],
): { content: (TextContent | ImageContent)[] } | undefined {
	const secrets = knownSecretValues();
	let changed = false;
	const redacted = content.map((part) => {
		if (part.type !== "text" || typeof part.text !== "string") return part;
		let text = part.text;
		if (secrets.length > 0) {
			const envResult = redactKnownSecrets(text, secrets);
			if (envResult.changed) {
				text = envResult.text;
				changed = true;
			}
		}
		const shapeResult = redactSecretShapes(text);
		if (shapeResult.changed) {
			text = shapeResult.text;
			changed = true;
		}
		return text === part.text ? part : { ...part, text };
	});
	return changed ? { content: redacted } : undefined;
}

function statusSummary(state: ReturnType<typeof loadState>): string {
	if (state.error) return `${state.error}\npatterns: ${state.rules.length}`;
	return `pi-cloak enabled=${state.config.enabled !== false} patterns=${state.rules.length} config=${state.configPath}`;
}

function cloakTextParts(
	content: (TextContent | ImageContent)[],
	rawPath: string,
	cwd: string,
	state: ReturnType<typeof loadState>,
): { content: (TextContent | ImageContent)[]; changed: boolean } {
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
