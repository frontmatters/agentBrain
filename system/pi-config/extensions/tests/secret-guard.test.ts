import assert from "node:assert/strict";
import test from "node:test";
import { secretGuardDecision } from "../secret-guard";

test("Pi decision blocks any tool input when scanner detects a secret", () => {
	for (const input of [{ command: "sensitive" }, { nested: [{ content: "sensitive" }] }]) {
		assert.deepEqual(secretGuardDecision(input, () => "Blocked: API key detected."), {
			block: true, reason: "Blocked: API key detected.",
		});
	}
});

test("Pi decision allows clean inputs and passes the whole input to scanner", () => {
	const input = { nested: [{ value: "clean" }] };
	assert.equal(secretGuardDecision(input, (received) => {
		assert.equal(received, input);
		return null;
	}), undefined);
});
