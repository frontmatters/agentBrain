import { readFile, readdir, stat } from "node:fs/promises";
import { join, relative } from "node:path";
import matter from "gray-matter";
import { brainRoot, brainPath } from "./brain";

const SEARCH_ROOTS = ["local", "system", "learnings"]; // private + public knowledge
const MAX_SNIPPET = 200;

// MCP scope boundary: paths no MCP client may search or read — security notes,
// biometric data (voiceprints/audio), addon configs (may hold endpoints/keys)
// and consent/pin records. Matched on the brain-relative path; read() refuses,
// search()/recent() silently skip.
const EXCLUDED = [
  /^local\/security\//,
  /^local\/addons\/[^/]+\/(voiceprint|audio)\//,
  /^local\/addons\/[^/]+\/(config\.json|channels\.json|settings\.json|\.consent|\.model-pin)$/,
];

export function isExcluded(relPath: string): boolean {
  const norm = relPath.replaceAll("\\", "/").replace(/^\.\//, "");
  return EXCLUDED.some((re) => re.test(norm));
}

// "Active space" session mode: when a context is set for the session, recall
// operates INSIDE that space — its notes ARE surfaced while every OTHER space
// stays sealed. Resolved from the per-session env ONLY (AGENTBRAIN_CONTEXT, with
// AGENTBRAIN_SPACE as a back-compat alias) — the same signal the write side infers
// (system/lib/context.sh). The old vault-global local/.active-space marker was
// decommissioned: it married work-context to storage and leaked across parallel
// sessions. Returns "" when no context is set (= default: all spaces excluded).
export function activeSpace(): string {
  const env = process.env.AGENTBRAIN_CONTEXT ?? process.env.AGENTBRAIN_SPACE;
  return env && env.trim() ? env.trim() : "";
}

// Yield every *.md under the search roots (absolute paths), skipping vendored
// node_modules and the MCP-excluded scope. Recursive readdir instead of Bun's
// Glob: the only Bun-specific API this server used, and dropping it lets the
// server run on plain node (via tsx) on hosts without bun.
async function* mdFiles(): AsyncGenerator<string> {
  const active = activeSpace();
  const activePrefix = active ? `local/spaces/${active}/` : "";
  for (const root of SEARCH_ROOTS) {
    let base: string;
    try { base = brainPath(root); } catch { continue; }
    let entries: string[];
    try { entries = (await readdir(base, { recursive: true })) as string[]; } catch { continue; /* root may not exist */ }
    for (const e of entries) {
      if (!e.endsWith(".md")) continue;
      const f = join(base, e);
      if (f.includes("/node_modules/")) continue;
      const rel = relative(brainRoot(), f);
      if (isExcluded(rel)) continue;
      // Spaces are sealed owner compartments — never surfaced by default recall.
      // Excluded here (enumeration) rather than in EXCLUDED so that an explicit
      // brain_read of a known space path still works (read() doesn't run mdFiles()).
      // Exception: the currently-active space (session mode) is let through, so
      // tooling can recall inside it; all other spaces stay sealed.
      if (/^local\/spaces\//.test(rel) && !(activePrefix && rel.startsWith(activePrefix))) continue;
      yield f;
    }
  }
}

function titleOf(content: string, fallback: string): string {
  let data: Record<string, unknown> = {};
  try { data = matter(content).data ?? {}; } catch { /* malformed frontmatter */ }
  const heading = content.match(/^#\s+(.+)$/m);
  return (data.title as string) || heading?.[1]?.trim() || fallback;
}

export interface Hit { path: string; title: string; snippet: string; }

// Case-insensitive substring search over path + content; capped at `limit` hits.
export async function search(query: string, limit = 20): Promise<Hit[]> {
  const q = query.toLowerCase();
  const hits: Hit[] = [];
  for await (const f of mdFiles()) {
    const rel = relative(brainRoot(), f);
    const content = await readFile(f, "utf8");
    const idx = content.toLowerCase().indexOf(q);
    const inPath = rel.toLowerCase().includes(q);
    if (idx === -1 && !inPath) continue;
    let snippet = "";
    if (idx !== -1) {
      const start = Math.max(0, idx - 60);
      snippet = content.slice(start, start + MAX_SNIPPET).replace(/\s+/g, " ").trim();
    }
    hits.push({ path: rel, title: titleOf(content, rel), snippet });
    if (hits.length >= limit) break;
  }
  return hits;
}

// Read a note by brain-relative path (guarded against traversal + MCP scope).
export async function read(relPath: string): Promise<string> {
  if (isExcluded(relPath)) {
    throw new Error(`refused: '${relPath}' is outside MCP scope (security/biometric/addon-config)`);
  }
  return readFile(brainPath(relPath), "utf8");
}

export interface RecentNote { path: string; title: string; mtime: string; }

// Most-recently-modified notes, newest first.
export async function recent(n = 10): Promise<RecentNote[]> {
  const all: { path: string; title: string; mtimeMs: number }[] = [];
  for await (const f of mdFiles()) {
    const s = await stat(f);
    const content = await readFile(f, "utf8");
    const rel = relative(brainRoot(), f);
    all.push({ path: rel, title: titleOf(content, rel), mtimeMs: s.mtimeMs });
  }
  all.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return all.slice(0, n).map(({ path, title, mtimeMs }) => ({
    path, title, mtime: new Date(mtimeMs).toISOString(),
  }));
}

// HOW/WHERE context: the brain's rules + skills index.
export async function rules(): Promise<string> {
  const parts: string[] = [];
  for (const p of ["system/rules.md", "system/skills.md"]) {
    try { parts.push(`# ${p}\n\n${await readFile(brainPath(p), "utf8")}`); } catch { /* absent */ }
  }
  return parts.join("\n\n---\n\n");
}
