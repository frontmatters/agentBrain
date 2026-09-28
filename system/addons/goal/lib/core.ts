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

// ── SMART gate + grill-me (agent-agnostic) ──────────────────────────────────
// A goal only auto-clears when a judge can call it "met" from transcript evidence.
// A vague goal ("close the gaps, document it") never verifies, so it lingers active
// forever. At set time we sharpen the raw condition via a 5WH pass (who/what/where/
// why/when + how). When it cannot be made verifiable from what the user gave, the
// consumer runs a grill-me: ask the user the missing facts, then set the SMART goal.
// Everything here is pure and framework-neutral, so any agent (pi, Claude Code, …)
// can reuse it; each agent supplies its own model call and UI glue.

export interface SmartRefinement {
	smart: string;
	verifiable: boolean;
	missing: string[];
	note: string;
}

export const GOAL_SMART_SYSTEM_PROMPT = `You turn a loosely phrased session goal into a SMART, verifiable stop-condition, using 5WH (who/what/where/why/when + how).
A stop-condition is verifiable only if a judge can answer "met" or "not met" from transcript evidence alone: WHAT is concrete and countable, WHERE names the files, systems or task-ids it touches, WHEN is bounded (this session or an explicit deadline), and HOW states the evidence of success (a passing test, a committed file, a screenshot, a green check).
Do not invent scope the user did not imply. If the goal cannot be made verifiable without facts only the user has (which gaps, which repo, what counts as done), set "verifiable" to false and list those missing facts as short, direct questions.
Respond with a JSON object:
{"smart": "<the sharpest verifiable condition you can form now>", "verifiable": <true|false>, "missing": ["<question 1>", "..."], "note": "<one line: what you sharpened or assumed>"}
If the original is already SMART and checkable, return it with "verifiable": true and "missing": [].`;

export const goalSmartPrompt = (condition: string): string =>
	`Turn this session goal into a SMART, verifiable stop-condition.\nOriginal goal: "${condition}"`;

// Returns null when the output is unusable, so the caller falls back to the user's
// original wording and never blocks goal-setting on a flaky model response.
export function parseSmartRefinement(text: string): SmartRefinement | null {
	try {
		const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1];
		const candidate = fenced ?? text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1);
		const value = JSON.parse(candidate) as Partial<SmartRefinement>;
		if (typeof value.smart !== "string" || !value.smart.trim()) return null;
		const missing = Array.isArray(value.missing)
			? value.missing.filter((q): q is string => typeof q === "string" && q.trim().length > 0).map((q) => q.trim())
			: [];
		return {
			smart: value.smart.trim(),
			verifiable: value.verifiable === true && missing.length === 0,
			missing,
			note: typeof value.note === "string" ? value.note.trim() : "",
		};
	} catch {
		return null;
	}
}

// The directive a consumer injects when a goal is not yet verifiable: the agent runs
// a grill-me on the missing facts, then sets the sharpened goal. Framework-neutral text.
export const goalGrillPrompt = (condition: string, missing: string[]): string =>
	`The goal "${condition}" is not yet a verifiable stop-condition, so it can never be checked off. Run a short grill-me: ask the user these questions one at a time to sharpen it:\n${missing.map((q, i) => `${i + 1}. ${q}`).join("\n")}\nThen set the goal with the sharpened SMART condition (a concrete target, where it lives, and the evidence that proves it done). Do not activate a vague goal.`;

// ── Goal log (agent-agnostic) ───────────────────────────────────────────────
// Every goal set and cleared is appended to a durable JSONL log, so there is a
// history: what was aimed for, when, and how it ended (achieved / abandoned /
// impossible / manual / auto-cleared-on-resume). This only shapes the line; the
// consumer owns the file write and its location (keep it off any synced vault, since
// a condition can carry confidential text).
export type GoalLogEvent = "set" | "cleared";

export function formatGoalLogEntry(event: GoalLogEvent, fields: Record<string, unknown>, ts: number): Record<string, unknown> {
	return { ts, iso: new Date(ts).toISOString(), event, ...fields };
}

// The log is partitioned per context (a space or a project), so agentBrain can read
// one project's goals without the others. A context is a safe slug; anything empty
// falls back to "personal".
export function sanitizeContext(raw: string): string {
	// No dots: the slug becomes a directory name, and "." / ".." would be traversal.
	const slug = raw.trim().toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "");
	return slug || "personal";
}

export function goalLogPath(baseDir: string, context: string): string {
	return `${baseDir}/${sanitizeContext(context)}/goals.jsonl`;
}

// The active-goal state file for a context (the file-based counterpart of pi's session
// state, so a standalone CLI or another agent can hold a goal too).
export function goalStatePath(baseDir: string, context: string): string {
	return `${baseDir}/${sanitizeContext(context)}/current.json`;
}

// Context priority, shared by every consumer: an explicit override wins, then the
// project (git repo) name, then "personal". Pure so the git lookup stays at the edge.
export function pickContext(envContext: string | undefined, projectName: string | undefined): string {
	return envContext?.trim() || projectName?.trim() || "personal";
}
