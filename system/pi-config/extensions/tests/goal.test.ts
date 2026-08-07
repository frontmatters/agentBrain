import assert from "node:assert/strict";
import test from "node:test";
import {
	buildGoalTranscript,
	GOAL_CLEAR_WORDS,
	GOAL_MAX_ITERATIONS,
	goalEvaluatorPrompt,
	goalKickoffPrompt,
	parseGoalVerdict,
	safeParseGoalVerdict,
} from "../goal-lib/core";

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
