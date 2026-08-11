export const GOAL_MAX_LENGTH = 4000;
export const GOAL_CLEAR_WORDS = new Set(["clear", "stop", "off", "reset", "none", "cancel"]);
export const GOAL_TRANSCRIPT_LIMIT = 100_000;
// Hard backstop on auto-continuation: if the goal is never verified (evaluator
// keeps returning not-met, or repeatedly returns unparseable output), abandon it
// after this many goal_check attempts instead of looping and burning tokens.
export const GOAL_MAX_ITERATIONS = 25;

export interface GoalState {
	condition: string;
	iterations: number;
	setAt: number;
	lastReason?: string;
}

interface MessageEntry {
	type: string;
	message?: {
		role?: string;
		content?: unknown;
	};
}

export interface GoalVerdict {
	ok: boolean;
	reason: string;
	impossible?: boolean;
}

export const goalKickoffPrompt = (condition: string): string =>
	`A session-scoped goal is now active with condition: "${condition}". Briefly acknowledge the goal, then immediately start (or continue) working toward it. Treat the condition itself as your directive and do not pause to ask the user what to do. Before stopping, call the goal_check tool. The goal auto-clears once the condition is met; /goal clear is only for stopping early.`;

export const goalTurnPrompt = (goal: GoalState): string =>
	`[GOAL ACTIVE]\nCondition: ${goal.condition}\nContinue working until this condition is demonstrably satisfied. Before stopping, you MUST call goal_check. Do not claim success without transcript evidence.`;

export const GOAL_EVALUATOR_SYSTEM_PROMPT = `You are evaluating a stop-condition hook in Pi. Read the conversation transcript carefully, then judge whether the user-provided condition is satisfied.
Your response must be a JSON object with one of these shapes:
- {"ok": true, "reason": "<quote evidence from the transcript that satisfies the condition>"}
- {"ok": false, "reason": "<quote what is missing or what blocks the condition>"}
- {"ok": false, "impossible": true, "reason": "<explain why the condition can never be satisfied>"}
Always include a "reason" field, quoting specific text from the transcript whenever possible. If the transcript does not contain clear evidence that the condition is satisfied, return {"ok": false, "reason": "insufficient evidence in transcript"}.
Only use {"ok": false, "impossible": true} when the condition is genuinely unachievable in this session. Do not use it just because progress is slow. When in doubt, return {"ok": false} without "impossible".`;

export const goalEvaluatorPrompt = (condition: string, transcript: string): string =>
	`<conversation>\n${transcript}\n</conversation>\n\nBased on the conversation transcript above, has the following stopping condition been satisfied? Answer based on transcript evidence only.\nCondition: ${condition}`;

function textFromContent(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.flatMap((block) => {
			if (!block || typeof block !== "object") return [];
			const value = block as { type?: string; text?: string; name?: string; arguments?: unknown };
			if (value.type === "text" && typeof value.text === "string") return [value.text];
			if (value.type === "toolCall" && typeof value.name === "string") {
				return [`[Tool call: ${value.name} ${JSON.stringify(value.arguments ?? {})}]`];
			}
			return [];
		})
		.join("\n");
}

export function buildGoalTranscript(entries: MessageEntry[], limit = GOAL_TRANSCRIPT_LIMIT): string {
	const sections: string[] = [];
	for (const entry of entries) {
		if (entry.type !== "message" || !entry.message?.role) continue;
		const text = textFromContent(entry.message.content).trim();
		if (text) sections.push(`${entry.message.role}: ${text}`);
	}
	const transcript = sections.join("\n\n");
	if (transcript.length <= limit) return transcript;
	return `[Earlier transcript omitted. If required evidence may be in the omitted prefix, return insufficient evidence.]\n\n${transcript.slice(-limit)}`;
}

export function parseGoalVerdict(text: string): GoalVerdict {
	const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1];
	const candidate = fenced ?? text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
	const value = JSON.parse(candidate) as Partial<GoalVerdict>;
	if (typeof value.ok !== "boolean" || typeof value.reason !== "string" || !value.reason.trim()) {
		throw new Error("Goal evaluator returned an invalid verdict");
	}
	return { ok: value.ok, reason: value.reason.trim(), impossible: value.impossible === true };
}

// Non-throwing wrapper for the tool call site: a malformed evaluator response
// must not crash goal_check (which would leave the goal active and let the
// auto-continuation hook re-trigger indefinitely). Treat unparseable output as
// "not met" so the normal not-met flow — and the iteration cap — take over.
export function safeParseGoalVerdict(text: string): GoalVerdict {
	try {
		return parseGoalVerdict(text);
	} catch (err) {
		const detail = err instanceof Error ? err.message : String(err);
		return { ok: false, reason: `evaluator returned unparseable output (${detail})` };
	}
}
