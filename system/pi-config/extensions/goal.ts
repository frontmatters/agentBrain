import { complete, type UserMessage } from "@earendil-works/pi-ai/compat";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
	buildGoalTranscript,
	GOAL_CLEAR_WORDS,
	GOAL_EVALUATOR_SYSTEM_PROMPT,
	GOAL_MAX_ITERATIONS,
	GOAL_MAX_LENGTH,
	goalEvaluatorPrompt,
	goalKickoffPrompt,
	goalTurnPrompt,
	safeParseGoalVerdict,
	type GoalState,
} from "./goal-lib/core";

const STATE_ENTRY = "agentbrain-goal-state";

interface StoredGoalEntry {
	type: string;
	customType?: string;
	data?: { goal?: GoalState };
}

function responseText(response: { content?: Array<{ type: string; text?: string }> }): string {
	if (!Array.isArray(response.content)) return "";
	return response.content
		.filter((block): block is { type: "text"; text: string } => block.type === "text" && typeof block.text === "string")
		.map((block) => block.text)
		.join("\n");
}

export default function goalExtension(pi: ExtensionAPI): void {
	let goal: GoalState | undefined;
	let continuationQueued = false;

	function persist(): void {
		pi.appendEntry(STATE_ENTRY, { goal });
	}

	function updateStatus(ctx: ExtensionContext): void {
		const label = goal ? `goal: ${goal.condition.length > 48 ? `${goal.condition.slice(0, 47)}…` : goal.condition}` : undefined;
		ctx.ui.setStatus("goal", label);
	}

	function clearGoal(ctx: ExtensionContext, message?: string): void {
		goal = undefined;
		continuationQueued = false;
		persist();
		updateStatus(ctx);
		if (message && ctx.hasUI) ctx.ui.notify(message, "info");
	}

	pi.registerCommand("goal", {
		description: "Set a session goal and keep working until it is verified",
		handler: async (args, ctx) => {
			const condition = args.trim();
			if (!condition) {
				ctx.ui.notify(goal ? `Goal active: ${goal.condition} (${goal.iterations} checks)` : "No goal set. Usage: /goal <condition>", "info");
				return;
			}
			if (GOAL_CLEAR_WORDS.has(condition.toLowerCase())) {
				const previous = goal?.condition;
				clearGoal(ctx, previous ? `Goal cleared: ${previous}` : "No goal set");
				return;
			}
			if (condition.length > GOAL_MAX_LENGTH) {
				ctx.ui.notify(`Goal condition is limited to ${GOAL_MAX_LENGTH} characters (got ${condition.length})`, "warning");
				return;
			}

			goal = { condition, iterations: 0, setAt: Date.now() };
			continuationQueued = false;
			persist();
			updateStatus(ctx);
			pi.sendMessage(
				{ customType: "goal-kickoff", content: goalKickoffPrompt(condition), display: true },
				{ triggerTurn: true },
			);
		},
	});

	pi.registerTool({
		name: "goal_check",
		label: "Goal Check",
		description: "Independently verify the active /goal against transcript evidence before stopping. Call only while a goal is active.",
		parameters: Type.Object({}),
		async execute(_toolCallId, _params, signal, _onUpdate, ctx) {
			if (!goal) {
				return { content: [{ type: "text" as const, text: "No active goal." }], details: { active: false }, terminate: true };
			}

			// Count every attempt before doing any work so a goal that is never
			// verified — or an evaluator/model that keeps failing — cannot loop
			// forever via the agent_settled continuation hook.
			goal.iterations += 1;
			if (goal.iterations > GOAL_MAX_ITERATIONS) {
				const condition = goal.condition;
				const last = goal.lastReason ? `\nLast check: ${goal.lastReason}` : "";
				clearGoal(ctx, `Goal abandoned after ${GOAL_MAX_ITERATIONS} checks: ${condition}`);
				return {
					content: [{ type: "text" as const, text: `Goal abandoned after ${GOAL_MAX_ITERATIONS} verification attempts without success: ${condition}${last}` }],
					details: { active: false, stoppedReason: "max-iterations", iterations: GOAL_MAX_ITERATIONS },
					terminate: true,
				};
			}

			if (!ctx.model) throw new Error("Cannot evaluate goal without an active model");

			const auth = await ctx.modelRegistry.getApiKeyAndHeaders(ctx.model);
			if (!auth.ok || !auth.apiKey) throw new Error(auth.ok ? `No API key for ${ctx.model.provider}` : auth.error);

			const evaluatorModel = `${ctx.model.provider}/${ctx.model.id}`;
			const transcript = buildGoalTranscript(ctx.sessionManager.getBranch());
			const message: UserMessage = {
				role: "user",
				content: [{ type: "text", text: goalEvaluatorPrompt(goal.condition, transcript) }],
				timestamp: Date.now(),
			};
			const response = await complete(
				ctx.model,
				{ systemPrompt: GOAL_EVALUATOR_SYSTEM_PROMPT, messages: [message] },
				{ apiKey: auth.apiKey, headers: auth.headers, env: auth.env, signal },
			);
			const verdict = safeParseGoalVerdict(responseText(response));
			goal.lastReason = verdict.reason;

			if (verdict.ok) {
				const condition = goal.condition;
				clearGoal(ctx);
				return {
					content: [{ type: "text" as const, text: `Goal achieved: ${condition}\nEvidence: ${verdict.reason}` }],
					details: { active: false, verdict, evaluatorModel },
					usage: response.usage,
					terminate: true,
				};
			}

			if (verdict.impossible) {
				const condition = goal.condition;
				clearGoal(ctx);
				return {
					content: [{ type: "text" as const, text: `Goal cannot be completed: ${condition}\nReason: ${verdict.reason}` }],
					details: { active: false, verdict, evaluatorModel },
					usage: response.usage,
					terminate: true,
				};
			}

			persist();
			updateStatus(ctx);
			return {
				content: [{ type: "text" as const, text: `Goal not met: ${verdict.reason}\nContinue working toward: ${goal.condition}` }],
				details: { active: true, verdict, iterations: goal.iterations, evaluatorModel },
				usage: response.usage,
			};
		},
	});

	pi.on("before_agent_start", async () => {
		if (!goal) return;
		return { message: { customType: "goal-context", content: goalTurnPrompt(goal), display: false } };
	});

	pi.on("agent_start", async () => {
		continuationQueued = false;
	});

	pi.on("agent_settled", async (_event, ctx) => {
		if (!goal || continuationQueued) return;
		continuationQueued = true;
		const reason = goal.lastReason ? ` Last check: ${goal.lastReason}` : "";
		pi.sendMessage(
			{
				customType: "goal-continue",
				content: `The active goal has not been verified yet.${reason} Continue working and call goal_check before stopping. Goal: ${goal.condition}`,
				display: true,
			},
			{ triggerTurn: true, deliverAs: "followUp" },
		);
		updateStatus(ctx);
	});

	pi.on("session_start", async (_event, ctx) => {
		const stored = ctx.sessionManager
			.getEntries()
			.filter((entry) => entry.type === "custom" && entry.customType === STATE_ENTRY)
			.pop() as StoredGoalEntry | undefined;
		goal = stored?.data?.goal;
		continuationQueued = false;
		updateStatus(ctx);
	});
}
