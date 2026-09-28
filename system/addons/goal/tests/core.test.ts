import assert from "node:assert/strict";
import test from "node:test";
import {
	buildGoalTranscript,
	GOAL_CLEAR_WORDS,
	GOAL_MAX_ITERATIONS,
	formatGoalLogEntry,
	GOAL_SMART_SYSTEM_PROMPT,
	goalEvaluatorPrompt,
	goalGrillPrompt,
	goalKickoffPrompt,
	goalLogPath,
	goalSmartPrompt,
	goalStatePath,
	parseGoalVerdict,
	parseSmartRefinement,
	pickContext,
	safeParseGoalVerdict,
	sanitizeContext,
} from "../lib/core";

test("goal command clear aliases are recognized", () => {
	for (const value of ["clear", "stop", "off", "reset", "none", "cancel"]) {
		assert.equal(GOAL_CLEAR_WORDS.has(value), true);
	}
});

test("kickoff prompt carries the condition and requires verification", () => {
	const prompt = goalKickoffPrompt("tests pass");
	assert.match(prompt, /tests pass/);
	assert.match(prompt, /goal_check/);
	assert.match(prompt, /immediately start/);
});

test("transcript includes user, assistant, and tool evidence", () => {
	const transcript = buildGoalTranscript([
		{ type: "message", message: { role: "user", content: [{ type: "text", text: "Fix it" }] } },
		{
			type: "message",
			message: {
				role: "assistant",
				content: [{ type: "toolCall", name: "bash", arguments: { command: "npm test" } }],
			},
		},
		{ type: "message", message: { role: "toolResult", content: [{ type: "text", text: "12 passed" }] } },
	]);
	assert.match(transcript, /user: Fix it/);
	assert.match(transcript, /Tool call: bash/);
	assert.match(transcript, /toolResult: 12 passed/);
});

test("transcript truncation keeps recent evidence", () => {
	const transcript = buildGoalTranscript(
		[
			{ type: "message", message: { role: "user", content: "old evidence" } },
			{ type: "message", message: { role: "assistant", content: "recent evidence" } },
		],
		20,
	);
	assert.match(transcript, /Earlier transcript omitted/);
	assert.match(transcript, /recent evidence/);
});

test("verdict parser accepts plain and fenced JSON", () => {
	assert.deepEqual(parseGoalVerdict('{"ok":true,"reason":"tests passed"}'), {
		ok: true,
		reason: "tests passed",
		impossible: false,
	});
	assert.deepEqual(parseGoalVerdict('```json\n{"ok":false,"impossible":true,"reason":"missing service"}\n```'), {
		ok: false,
		reason: "missing service",
		impossible: true,
	});
});

test("verdict parser rejects missing evidence reason", () => {
	assert.throws(() => parseGoalVerdict('{"ok":true}'), /invalid verdict/);
});

test("safe verdict parser never throws on unparseable output", () => {
	for (const garbage of ["", "yes", "Here is a poem, no JSON here", "{not json}", '{"ok":true}']) {
		const verdict = safeParseGoalVerdict(garbage);
		assert.equal(verdict.ok, false);
		assert.equal(typeof verdict.reason, "string");
		assert.ok(verdict.reason.length > 0);
	}
});

test("safe verdict parser passes valid verdicts through unchanged", () => {
	assert.deepEqual(safeParseGoalVerdict('{"ok":true,"reason":"tests passed"}'), {
		ok: true,
		reason: "tests passed",
		impossible: false,
	});
});

test("iteration cap is a positive backstop", () => {
	assert.equal(typeof GOAL_MAX_ITERATIONS, "number");
	assert.ok(GOAL_MAX_ITERATIONS > 0);
});

test("evaluator prompt separates transcript and condition", () => {
	const prompt = goalEvaluatorPrompt("lint passes", "assistant: fixed it");
	assert.match(prompt, /<conversation>/);
	assert.match(prompt, /assistant: fixed it/);
	assert.match(prompt, /Condition: lint passes/);
});

test("SMART system prompt applies 5WH and demands verifiability", () => {
	assert.match(GOAL_SMART_SYSTEM_PROMPT, /5WH/);
	assert.match(GOAL_SMART_SYSTEM_PROMPT, /verifiable/i);
	assert.match(GOAL_SMART_SYSTEM_PROMPT, /"missing"/);
});

test("SMART prompt carries the original goal", () => {
	assert.match(goalSmartPrompt("ship it"), /ship it/);
});

test("SMART parser: verifiable refinement (no missing)", () => {
	const r = parseSmartRefinement('{"smart":"#20 and #260 on done with a restore-test each","verifiable":true,"missing":[],"note":"scoped to two tasks"}');
	assert.deepEqual(r, {
		smart: "#20 and #260 on done with a restore-test each",
		verifiable: true,
		missing: [],
		note: "scoped to two tasks",
	});
});

test("SMART parser: missing facts force verifiable=false even if the model claims true", () => {
	const r = parseSmartRefinement('{"smart":"close the gaps","verifiable":true,"missing":["Which gaps?","In which repo?"],"note":""}');
	assert.ok(r);
	assert.equal(r?.verifiable, false);
	assert.deepEqual(r?.missing, ["Which gaps?", "In which repo?"]);
});

test("SMART parser: fenced JSON and unusable output", () => {
	assert.equal(parseSmartRefinement('```json\n{"smart":"x is green","verifiable":true,"missing":[]}\n```')?.smart, "x is green");
	for (const garbage of ["", "no json", "{not json}", '{"verifiable":true}']) {
		assert.equal(parseSmartRefinement(garbage), null);
	}
});

test("grill prompt lists the missing questions and forbids a vague goal", () => {
	const prompt = goalGrillPrompt("dicht de gaps", ["Which gaps?", "What is the deadline?"]);
	assert.match(prompt, /grill-me/);
	assert.match(prompt, /1\. Which gaps\?/);
	assert.match(prompt, /2\. What is the deadline\?/);
	assert.match(prompt, /Do not activate a vague goal/);
});

test("log entry carries a timestamp, iso, event and the fields", () => {
	const entry = formatGoalLogEntry("cleared", { condition: "x done", outcome: "achieved" }, 1_700_000_000_000);
	assert.deepEqual(entry, {
		ts: 1_700_000_000_000,
		iso: "2023-11-14T22:13:20.000Z",
		event: "cleared",
		condition: "x done",
		outcome: "achieved",
	});
});

test("context sanitizes to a safe slug and falls back to personal", () => {
	assert.equal(sanitizeContext("Client Space"), "client-space");
	assert.equal(sanitizeContext("some-project-phase0"), "some-project-phase0");
	assert.equal(sanitizeContext("  --weird/../name-- "), "weird-name");
	assert.equal(sanitizeContext(""), "personal");
	assert.equal(sanitizeContext("../../etc"), "etc");
	assert.equal(sanitizeContext("///"), "personal");
});

test("log path partitions per context under the base dir", () => {
	assert.equal(goalLogPath("/base/goal-logs", "Client Space"), "/base/goal-logs/client-space/goals.jsonl");
	assert.equal(goalLogPath("/base", ""), "/base/personal/goals.jsonl");
});

test("state path sits next to the log per context", () => {
	assert.equal(goalStatePath("/base", "Client Space"), "/base/client-space/current.json");
	assert.equal(goalStatePath("/base", ""), "/base/personal/current.json");
});

test("context priority: override, then project, then personal", () => {
	assert.equal(pickContext("space-x", "repo-y"), "space-x");
	assert.equal(pickContext(undefined, "repo-y"), "repo-y");
	assert.equal(pickContext("  ", ""), "personal");
	assert.equal(pickContext("", undefined), "personal");
});
