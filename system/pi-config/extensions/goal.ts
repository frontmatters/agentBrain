import { execFileSync } from "node:child_process";
import { appendFileSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { complete, type UserMessage } from "@earendil-works/pi-ai/compat";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
	buildGoalTranscript,
	formatGoalLogEntry,
	type GoalLogEvent,
	GOAL_CLEAR_WORDS,
	GOAL_EVALUATOR_SYSTEM_PROMPT,
	GOAL_MAX_ITERATIONS,
	GOAL_MAX_LENGTH,
	GOAL_SMART_SYSTEM_PROMPT,
	goalEvaluatorPrompt,
	goalGrillPrompt,
	goalKickoffPrompt,
	goalLogPath,
	goalSmartPrompt,
	goalTurnPrompt,
	parseSmartRefinement,
	safeParseGoalVerdict,
	type GoalState,
	type SmartRefinement,
} from "../../addons/goal/lib/core";

// A goal belongs to a context: a space (e.g. acme) or a project. The log is
// partitioned by it so agentBrain can read one project's goals in isolation.
// GOAL_LOG_CONTEXT wins (set it to a space slug); else the git repo name; else personal.
function resolveContext(): string {
	if (process.env.GOAL_LOG_CONTEXT) return process.env.GOAL_LOG_CONTEXT;
	try {
		const top = execFileSync("git", ["rev-parse", "--show-toplevel"], { stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
		if (top) return basename(top);
	} catch {
		// not a git repo
	}
	return "personal";
}

// The log file for the current context. GOAL_LOG_PATH forces an explicit file (used by
// tests). Default base is a sibling of the vault, so it stays LOCAL and unsynced: a
// condition can carry confidential text and must not leak to Gitea.
function goalLogFile(): string {
	if (process.env.GOAL_LOG_PATH) return process.env.GOAL_LOG_PATH;
	const base = process.env.GOAL_LOG_DIR ?? join(homedir(), ".agentBrain", "goal-logs");
	return goalLogPath(base, resolveContext());
}

// Append-only history of every goal (set + cleared). Never throws.
function logGoal(event: GoalLogEvent, fields: Record<string, unknown>): void {
	try {
		const path = goalLogFile();
		mkdirSync(dirname(path), { recursive: true });
		appendFileSync(path, `${JSON.stringify(formatGoalLogEntry(event, { context: resolveContext(), ...fields }, Date.now()))}\n`);
	} catch {
		// logging must never break goal-setting or clearing
	}
}

// Render the last `n` log lines of the current context for a human or agentBrain.
function readGoalLog(n: number): string {
	try {
		const lines = readFileSync(goalLogFile(), "utf8").trim().split("\n").filter(Boolean);
		if (lines.length === 0) return "Goal log is empty for this context.";
		return lines
			.slice(-n)
			.map((line) => {
				try {
					const e = JSON.parse(line) as { iso?: string; event?: string; outcome?: string; condition?: string };
					const tag = e.event === "cleared" ? `cleared/${e.outcome ?? "?"}` : "set";
					return `${e.iso ?? "?"}  ${tag}  ${e.condition ?? ""}`;
				} catch {
					return line;
				}
			})
			.join("\n");
	} catch {
		return "No goal log yet for this context.";
	}
}

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

	function clearGoal(ctx: ExtensionContext, message?: string, outcome = "manual"): void {
		if (goal) logGoal("cleared", { condition: goal.condition, outcome, iterations: goal.iterations, reason: goal.lastReason });
		goal = undefined;
		continuationQueued = false;
		persist();
		updateStatus(ctx);
		if (message && ctx.hasUI) ctx.ui.notify(message, "info");
	}

	// Shared evaluator: judge the active goal against transcript evidence. Used by
	// goal_check (before stopping) and by the resume-recheck on session_start.
	async function runEvaluator(ctx: ExtensionContext, signal?: AbortSignal) {
		if (!goal) throw new Error("No active goal to evaluate");
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
		return { verdict: safeParseGoalVerdict(responseText(response)), evaluatorModel, usage: response.usage };
	}

	// SMART gate: sharpen the raw condition into a verifiable stop-condition via 5WH.
	// Falls back to the user's wording (verifiable) if no model is available, so goal
	// setting is never blocked by a flaky refiner.
	async function refineToSmart(ctx: ExtensionContext, condition: string): Promise<SmartRefinement> {
		const fallback: SmartRefinement = { smart: condition, verifiable: true, missing: [], note: "" };
		try {
			if (!ctx.model) return fallback;
			const auth = await ctx.modelRegistry.getApiKeyAndHeaders(ctx.model);
			if (!auth.ok || !auth.apiKey) return fallback;
			const message: UserMessage = {
				role: "user",
				content: [{ type: "text", text: goalSmartPrompt(condition) }],
				timestamp: Date.now(),
			};
			const response = await complete(
				ctx.model,
				{ systemPrompt: GOAL_SMART_SYSTEM_PROMPT, messages: [message] },
				{ apiKey: auth.apiKey, headers: auth.headers, env: auth.env },
			);
			return parseSmartRefinement(responseText(response)) ?? fallback;
		} catch {
			return fallback;
		}
	}

	pi.registerCommand("goal", {
		description: "Set a session goal and keep working until it is verified",
		handler: async (args, ctx) => {
			const condition = args.trim();
			if (!condition) {
				ctx.ui.notify(goal ? `Goal active: ${goal.condition} (${goal.iterations} checks)` : "No goal set. Usage: /goal <condition> | /goal log [n]", "info");
				return;
			}
			const lower = condition.toLowerCase();
			if (lower === "log" || lower.startsWith("log ")) {
				const n = Number.parseInt(condition.slice(3).trim(), 10);
				ctx.ui.notify(`Goal log (${resolveContext()}):\n${readGoalLog(Number.isFinite(n) && n > 0 ? n : 10)}`, "info");
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

			// SMART gate: a goal only auto-clears if it is verifiable. Sharpen it via 5WH.
			const refinement = await refineToSmart(ctx, condition);
			if (!refinement.verifiable) {
				// Not afmeldbaar yet: grill the user instead of activating a vague goal.
				if (ctx.hasUI) ctx.ui.notify("Goal is not verifiable yet — grilling you to make it SMART before activating.", "info");
				pi.sendMessage(
					{ customType: "goal-grill", content: goalGrillPrompt(condition, refinement.missing), display: true },
					{ triggerTurn: true },
				);
				return;
			}

			const finalCondition = refinement.smart;
			goal = { condition: finalCondition, iterations: 0, setAt: Date.now() };
			continuationQueued = false;
			persist();
			updateStatus(ctx);
			logGoal("set", { condition: finalCondition, original: condition, sharpened: finalCondition !== condition, note: refinement.note });
			if (ctx.hasUI && finalCondition !== condition) {
				ctx.ui.notify(`Goal sharpened to SMART:\n${finalCondition}${refinement.note ? `\n(${refinement.note})` : ""}`, "info");
			}
			pi.sendMessage(
				{ customType: "goal-kickoff", content: goalKickoffPrompt(finalCondition), display: true },
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
				clearGoal(ctx, `Goal abandoned after ${GOAL_MAX_ITERATIONS} checks: ${condition}`, "abandoned");
				return {
					content: [{ type: "text" as const, text: `Goal abandoned after ${GOAL_MAX_ITERATIONS} verification attempts without success: ${condition}${last}` }],
					details: { active: false, stoppedReason: "max-iterations", iterations: GOAL_MAX_ITERATIONS },
					terminate: true,
				};
			}

			const { verdict, evaluatorModel, usage } = await runEvaluator(ctx, signal);
			goal.lastReason = verdict.reason;

			if (verdict.ok) {
				const condition = goal.condition;
				clearGoal(ctx, undefined, "achieved");
				return {
					content: [{ type: "text" as const, text: `Goal achieved: ${condition}\nEvidence: ${verdict.reason}` }],
					details: { active: false, verdict, evaluatorModel },
					usage,
					terminate: true,
				};
			}

			if (verdict.impossible) {
				const condition = goal.condition;
				clearGoal(ctx, undefined, "impossible");
				return {
					content: [{ type: "text" as const, text: `Goal cannot be completed: ${condition}\nReason: ${verdict.reason}` }],
					details: { active: false, verdict, evaluatorModel },
					usage,
					terminate: true,
				};
			}

			persist();
			updateStatus(ctx);
			return {
				content: [{ type: "text" as const, text: `Goal not met: ${verdict.reason}\nContinue working toward: ${goal.condition}` }],
				details: { active: true, verdict, iterations: goal.iterations, evaluatorModel },
				usage,
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

		// Resume-recheck: a goal that was achieved out of band (in another agent, or
		// while this session was idle) must auto-clear when the session reloads, not
		// linger active for days. Re-evaluate once here; leave it as-is if it fails.
		if (goal && ctx.model) {
			try {
				const { verdict } = await runEvaluator(ctx);
				if (verdict.ok) {
					clearGoal(ctx, `Goal auto-cleared on resume (already achieved): ${goal.condition}`, "achieved-on-resume");
				} else if (verdict.impossible) {
					clearGoal(ctx, `Goal cleared on resume (no longer achievable): ${goal.condition}`, "impossible-on-resume");
				} else {
					goal.lastReason = verdict.reason;
					persist();
					updateStatus(ctx);
				}
			} catch {
				// keep the goal active if the recheck cannot run (no auth, offline, …)
			}
		}
	});
}
