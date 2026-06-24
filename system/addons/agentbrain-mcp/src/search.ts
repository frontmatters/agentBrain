import { Glob } from "bun";
import { readFile, stat } from "node:fs/promises";
import { relative } from "node:path";
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

// Yield every *.md under the search roots (absolute paths), skipping vendored
// node_modules and the MCP-excluded scope.
async function* mdFiles(): AsyncGenerator<string> {
  const glob = new Glob("**/*.md");
  for (const root of SEARCH_ROOTS) {
    let base: string;
    try { base = brainPath(root); } catch { continue; }
    try {
      for await (const f of glob.scan({ cwd: base, absolute: true })) {
        if (f.includes("/node_modules/")) continue;
        if (isExcluded(relative(brainRoot(), f))) continue;
        yield f;
      }
    } catch { /* root may not exist */ }
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
