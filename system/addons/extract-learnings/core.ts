#!/usr/bin/env bun
// extract-learnings core — transcript -> learnings -> local/learnings/extracted/.
import { readFile, writeFile, mkdir } from "fs/promises";
import { existsSync } from "fs";
import { join, dirname, resolve } from "path";
import { createHash } from "crypto";
import { callModel } from "../youtube-digest/src/summarizer";

const SCRIPT_DIR = dirname(Bun.main);                    // the add-on dir (core.ts is run directly)
const BRAIN = resolve(SCRIPT_DIR, "..", "..", "..");      // brain root: addons/<id> -> addons -> system -> root
// Output dir + timeout are env-overridable so tests can run isolated (tmpdir) and
// fast; production defaults are unchanged when the vars are unset.
const OUT_DIR = process.env.EXTRACT_LEARNINGS_OUT_DIR ?? join(BRAIN, "local", "learnings", "extracted");
const MODEL_TIMEOUT_MS = Number(process.env.EXTRACT_LEARNINGS_TIMEOUT_MS ?? 60_000); // never hang a hook

// Flatten a Claude .jsonl transcript into plain text (user+assistant turns only).
export function transcriptToText(jsonl: string): string {
  const lines: string[] = [];
  for (const raw of jsonl.split("\n")) {
    if (!raw.trim()) continue;
    let e: any; try { e = JSON.parse(raw); } catch { continue; }
    const msg = e.message ?? e;
    const role = msg.role;
    if (role !== "user" && role !== "assistant") continue;
    const c = msg.content;
    const text = typeof c === "string" ? c
      : Array.isArray(c) ? c.map((p: any) => p?.text ?? "").join(" ") : "";
    if (text.trim()) lines.push(`${role}: ${text.trim()}`);
  }
  return lines.join("\n").slice(-16000); // tail: most recent context
}

export function buildPrompt(text: string): string {
  return `Extract 0-5 durable, reusable LEARNINGS from this coding session (skip trivial/one-off).
Each on its own line as: LEARNING: <one actionable sentence>. If nothing durable, output nothing.

Session:
${text}`;
}

async function loadSettings(): Promise<any> {
  // Reuse the youtube-digest summarizer config if present; else empty (Pi fallback).
  const p = join(BRAIN, "local", "addons", "youtube-digest", "channels.json");
  if (existsSync(p)) { try { return JSON.parse(await readFile(p, "utf-8")).settings ?? {}; } catch {} }
  return {};
}

export async function extractFromTranscript(jsonlPath: string): Promise<number> {
  if (!existsSync(jsonlPath)) return 0;
  const text = transcriptToText(await readFile(jsonlPath, "utf-8"));
  if (text.split(/\s+/).length < 50) return 0;            // too short to be worth it
  // Bound the model call so a slow/hanging provider (e.g. an offline Pi fallback) never stalls.
  const out = await Promise.race([
    callModel(buildPrompt(text), await loadSettings(), { assumeYes: true }),
    new Promise<null>((r) => setTimeout(() => r(null), MODEL_TIMEOUT_MS)),
  ]);
  if (!out) return 0;
  const learnings = [...out.matchAll(/^LEARNING:\s*(.+)$/gm)].map(m => m[1].trim()).filter(Boolean);
  if (!learnings.length) return 0;
  await mkdir(OUT_DIR, { recursive: true });
  let written = 0;
  for (const l of learnings) {
    const id = createHash("sha1").update(l).digest("hex").slice(0, 12);
    const file = join(OUT_DIR, `${new Date().toISOString().slice(0,10)}-${id}.md`);
    if (existsSync(file)) continue;                       // dedup by content hash
    await writeFile(file, `---\ndate: ${new Date().toISOString().slice(0,10)}\ntype: learning\ntags: [extracted, session]\nconfidence: low\nsource: session\n---\n\n# ${l}\n`);
    written++;
  }
  return written;
}

if (import.meta.main) {
  const n = await extractFromTranscript(process.argv[2] ?? "");
  console.log(`extract-learnings: wrote ${n} learning(s)`);
  // Force exit: the bounding setTimeout (or a hung fallback) would otherwise keep the
  // event loop alive after the work is already done. Writes are awaited above, so safe.
  process.exit(0);
}
