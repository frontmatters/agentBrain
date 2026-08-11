import assert from "node:assert/strict";
import test from "node:test";
import { gunzipSync, gzipSync } from "node:zlib";

function parseMaybeGzipJson(buffer) {
	const body =
		buffer[0] === 0x1f && buffer[1] === 0x8b
			? gunzipSync(buffer).toString("utf8")
			: buffer.toString("utf8");
	return JSON.parse(body);
}

test("parseMaybeGzipJson parses plain JSON buffers", () => {
	const parsed = parseMaybeGzipJson(Buffer.from('{"ok":true}', "utf8"));
	assert.deepEqual(parsed, { ok: true });
});

test("parseMaybeGzipJson parses gzip-compressed JSON buffers by magic bytes", () => {
	const gzipped = gzipSync(Buffer.from('{"token":"abc","expires_at":123}', "utf8"));
	assert.equal(gzipped[0], 0x1f);
	assert.equal(gzipped[1], 0x8b);
	const parsed = parseMaybeGzipJson(gzipped);
	assert.deepEqual(parsed, { token: "abc", expires_at: 123 });
});
