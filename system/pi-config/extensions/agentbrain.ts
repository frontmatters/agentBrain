import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { buildAgentBrainSystemPrompt } from "./agentbrain-lib/prompt";
import { handleSessionStart, runStatusTool } from "./agentbrain-lib/status";
import {
	runProjectContextTool,
	runReadTool,
	runSearchTool,
} from "./agentbrain-lib/tools";

function registerAgentBrainEvents(pi: ExtensionAPI): void {
	pi.on("session_start", (_event, ctx) => handleSessionStart(ctx));

	pi.on("before_agent_start", async (event, ctx) => ({
		systemPrompt: await buildAgentBrainSystemPrompt(event.systemPrompt, ctx),
	}));
}

function registerAgentBrainStatusTool(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "agentbrain_status",
		label: "agentBrain Status",
		description:
			"Show agentBrain integration status, core files, detected project context, and setup warnings.",
		promptSnippet:
			"Inspect the user's agentBrain persistent memory setup and detected project context",
		promptGuidelines: [
			"Use agentbrain_status when you need to understand the current agentBrain/Pi memory integration or detected project context.",
		],
		parameters: Type.Object({}),
		async execute(_toolCallId, _params, _signal, _onUpdate, ctx) {
			return runStatusTool(ctx);
		},
	});
}

function registerAgentBrainReadTool(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "agentbrain_read",
		label: "agentBrain Read",
		description:
			"Read one or more files from agentBrain. Paths must be inside the configured agentBrain directory. Output is capped at 50KB per file.",
		promptSnippet: "Read selected persistent memory files from agentBrain",
		promptGuidelines: [
			"Use agentbrain_read to load known agentBrain files instead of shelling out with cat or sed.",
		],
		parameters: Type.Object({
			paths: Type.Array(
				Type.String({
					description: "Relative or absolute paths inside agentBrain",
				}),
			),
		}),
		async execute(_toolCallId, params) {
			return runReadTool(params);
		},
	});
}

function registerAgentBrainSearchTool(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "agentbrain_search",
		label: "agentBrain Search",
		description:
			"Search markdown notes in agentBrain. Scopes: all, shared, local, projects. Returns matching file/line snippets, capped by maxResults.",
		promptSnippet:
			"Search the user's persistent agentBrain notes by text query",
		promptGuidelines: [
			"Use agentbrain_search when the user asks about prior knowledge, preferences, project notes, or reusable troubleshooting history.",
		],
		parameters: Type.Object({
			query: Type.String({
				description: "Case-insensitive text to search for",
			}),
			scope: Type.Optional(
				Type.String({ description: "all, shared, local, or projects" }),
			),
			maxResults: Type.Optional(
				Type.Number({
					description: "Maximum matching lines to return, default 40",
				}),
			),
		}),
		async execute(_toolCallId, params) {
			return runSearchTool(params);
		},
	});
}

function registerAgentBrainProjectContextTool(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "agentbrain_project_context",
		label: "agentBrain Project Context",
		description:
			"Load the detected or named project context from agentBrain/local/projects/<project> including index, PRD, decisions, deploy, changelog, and context files when present.",
		promptSnippet:
			"Load project-specific persistent memory from agentBrain/local/projects",
		promptGuidelines: [
			"Use agentbrain_project_context before making project-specific decisions when a project note may exist.",
		],
		parameters: Type.Object({
			project: Type.Optional(
				Type.String({
					description:
						"Project folder name under local/projects; omit for auto-detection",
				}),
			),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			return runProjectContextTool(params, ctx);
		},
	});
}

function registerAgentBrainTools(pi: ExtensionAPI): void {
	registerAgentBrainStatusTool(pi);
	registerAgentBrainReadTool(pi);
	registerAgentBrainSearchTool(pi);
	registerAgentBrainProjectContextTool(pi);
}

export default function agentBrainExtension(pi: ExtensionAPI): void {
	registerAgentBrainEvents(pi);
	registerAgentBrainTools(pi);
}
