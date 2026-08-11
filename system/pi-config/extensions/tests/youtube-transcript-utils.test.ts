import assert from "node:assert/strict";
import test from "node:test";
import {
	cleanVttToText,
	formatUploadDate,
	sanitizeFilePart,
} from "../youtube-transcript-utils";

test("cleanVttToText removes VTT metadata, timestamps, tags, entities, and duplicate cues", () => {
	const vtt = `WEBVTT
Kind: captions
Language: en

1
00:00:00.000 --> 00:00:02.000
<v Speaker>Hello &amp; welcome</v>

2
00:00:02.000 --> 00:00:04.000
<v Speaker>Hello &amp; welcome</v>

NOTE ignored
3
00:00:04.000 --> 00:00:06.000
Second &lt;line&gt; &#39;ok&#39;`;

	assert.equal(cleanVttToText(vtt), "Hello & welcome\nSecond <line> 'ok'");
});

test("sanitizeFilePart creates filesystem-safe slugs with fallback", () => {
	assert.equal(sanitizeFilePart(" A/B: C? #1 "), "A-B-C-1");
	assert.equal(sanitizeFilePart("////", "fallback"), "fallback");
});

test("formatUploadDate converts yt-dlp dates and falls back for invalid values", () => {
	assert.equal(formatUploadDate("20260518"), "2026-05-18");
	assert.match(formatUploadDate("bad"), /^\d{4}-\d{2}-\d{2}$/);
});
