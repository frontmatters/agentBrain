// Network-free tests for the extract-learnings core.
// The model call (callModel) is mocked, so nothing leaves the machine; output goes
// to a tmpdir via EXTRACT_LEARNINGS_OUT_DIR.
import { test, expect, mock, beforeAll, afterAll } from "bun:test";
import { mkdtemp, writeFile, readdir, rm, readFile } from "fs/promises";
import { tmpdir } from "os";
import { join } from "path";

// --- Mock the summarizer so no network call is ever made. ---
// `__MOCK` lets each test decide what callModel returns (or whether it "hangs").
const ctrl: { mode: "lines" | "empty" | "null" | "hang"; payload?: string } = { mode: "null" };
mock.module("../../youtube-knowledge/src/summarizer", () => ({
  callModel: async (_prompt: string) => {
    switch (ctrl.mode) {
      case "lines": return ctrl.payload ?? "LEARNING: always pin npm versions\nLEARNING: log skipped deps";
      case "empty": return "";
      case "hang":  return await new Promise<string>(() => {}); // never resolves -> timeout wins
      default:      return null as unknown as string;
    }
  },
}));

let OUT: string;
let mod: typeof import("../core");

beforeAll(async () => {
  OUT = await mkdtemp(join(tmpdir(), "extract-learnings-"));
  process.env.EXTRACT_LEARNINGS_OUT_DIR = OUT;
  process.env.EXTRACT_LEARNINGS_TIMEOUT_MS = "150"; // fast timeout for the hang test
  mod = await import("../core");
});

afterAll(async () => {
  await rm(OUT, { recursive: true, force: true });
});

// --- Pure helpers ---
test("transcriptToText keeps user/assistant turns, drops other roles + junk", () => {
  const jsonl = [
    JSON.stringify({ message: { role: "user", content: "hello there" } }),
    JSON.stringify({ message: { role: "assistant", content: [{ text: "hi back" }] } }),
    JSON.stringify({ message: { role: "system", content: "ignored" } }),
    "not json at all",
    "",
  ].join("\n");
  const out = mod.transcriptToText(jsonl);
  expect(out).toContain("user: hello there");
  expect(out).toContain("assistant: hi back");
  expect(out).not.toContain("ignored");
});

test("buildPrompt embeds the session text and the LEARNING instruction", () => {
  const p = mod.buildPrompt("some session body");
  expect(p).toContain("LEARNING:");
  expect(p).toContain("some session body");
});

// --- extractFromTranscript control flow ---
async function makeTranscript(words: number): Promise<string> {
  const body = Array.from({ length: words }, (_, i) => `word${i}`).join(" ");
  const f = join(OUT, `transcript-${words}-${Math.random().toString(36).slice(2)}.jsonl`);
  await writeFile(f, JSON.stringify({ message: { role: "user", content: body } }) + "\n");
  return f;
}

test("missing transcript path -> 0, writes nothing", async () => {
  ctrl.mode = "lines";
  expect(await mod.extractFromTranscript(join(OUT, "does-not-exist.jsonl"))).toBe(0);
});

test("too-short transcript is skipped before any model call", async () => {
  ctrl.mode = "lines";
  const f = await makeTranscript(10); // < 50 words
  expect(await mod.extractFromTranscript(f)).toBe(0);
});

test("model returns LEARNING lines -> files written + deduped by content", async () => {
  ctrl.mode = "lines";
  ctrl.payload = "LEARNING: pin npm versions\nLEARNING: log skipped deps\nLEARNING: pin npm versions";
  const f = await makeTranscript(80);
  const before = (await readdir(OUT)).filter((n) => n.endsWith(".md")).length;
  const n = await mod.extractFromTranscript(f);
  expect(n).toBe(2); // 3 lines, one duplicate collapsed
  const after = (await readdir(OUT)).filter((n) => n.endsWith(".md"));
  expect(after.length).toBe(before + 2);
  const sample = await readFile(join(OUT, after[0]), "utf-8");
  expect(sample).toContain("type: learning");
});

test("empty model output -> 0 written", async () => {
  ctrl.mode = "empty";
  const f = await makeTranscript(80);
  expect(await mod.extractFromTranscript(f)).toBe(0);
});

test("model hang is bounded by the timeout -> 0 (never stalls the hook)", async () => {
  ctrl.mode = "hang";
  const f = await makeTranscript(80);
  const t0 = Date.now();
  const n = await mod.extractFromTranscript(f);
  const elapsed = Date.now() - t0;
  expect(n).toBe(0);
  expect(elapsed).toBeLessThan(2000); // timeout (150ms) fired well before any real model call
});
