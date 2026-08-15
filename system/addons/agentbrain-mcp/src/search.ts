import { readFile, readdir, stat } from "node:fs/promises";
import { readFileSync } from "node:fs";
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

// Recall noise, as opposed to the security boundary above. These areas are real
// files that should not compete with knowledge for a slot in the results:
// deliberately deleted notes, machine-generated graph reports, quarantined input.
// `.trash/forget/` is the sharpest case — measured on the live vault, deleted notes
// took the top slot on 4 of 9 sample queries, because a dot-prefixed directory sorts
// first and the score tie-break falls back to path order. A forget feature that
// leaves its notes in the search index does not forget.
//
// This is a skiplist, not a security control: brain_read on a known path still works,
// so nothing becomes unreachable — only unranked.
const DEFAULT_SKIP = ["local/.trash/", "local/graphify-out/", "local/quarantine/"];

// Vault-local override at `local/.searchignore`: one brain-relative path prefix per
// line, `#` for comments, and a leading `!` to re-admit one of the defaults. Prefixes
// rather than globs on purpose — every case this exists for is "an entire directory",
// and a glob dialect is a thing to learn, document and get wrong.
export function skipPrefixes(): string[] {
  const skip = new Set(DEFAULT_SKIP);
  let lines: string[];
  try {
    lines = readFileSync(join(brainRoot(), "local", ".searchignore"), "utf8").split("\n");
  } catch {
    return [...skip]; // absent file is the normal case
  }
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    if (line.startsWith("!")) skip.delete(line.slice(1).trim());
    else skip.add(line);
  }
  return [...skip];
}

export function isSkipped(relPath: string, prefixes = skipPrefixes()): boolean {
  const norm = relPath.replaceAll("\\", "/").replace(/^\.\//, "");
  return prefixes.some((p) => norm === p || norm.startsWith(p));
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
  const skip = skipPrefixes(); // read the ignore file once per enumeration, not per file
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
      if (isSkipped(rel, skip)) continue;
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

export interface Hit {
  path: string;
  title: string;
  snippet: string;
  score: number;
  /** Substitutions this hit needed, e.g. ["tokne→token"]. Absent on exact hits. */
  fuzzy?: string[];
}

// --- fuzzy recall -----------------------------------------------------------
//
// Lexical matching alone misses two things people actually type: inflections
// ("asserties" will not find "assertie" — substring only works in the other
// direction) and typos. Measured on the live vault, both cost the correct note its
// top slot. Neither is solved by matching harder; they need a vocabulary to match
// *against*.
//
// No index is persisted: the vocabulary is built on demand and thrown away, so there
// is no cache to invalidate, no staleness check, and no file on disk that can
// disagree with the vault. It is built in its OWN pass rather than during scoring —
// collecting it in the scoring pass made every query pay for it, and an exact query
// went from 0.6s to 2.9s on the live vault because tokenising 50MB is not free. Now
// the common query never tokenises anything, and only a query that needs fuzzy
// recall pays for the extra passes.

const FUZZY_MIN_LEN = 5; // below this a typo is indistinguishable from a different word
const FUZZY_WEIGHT = 0.5; // reporting weight only — ranking keeps exact and fuzzy apart
const FUZZY_MAX_EXPANSIONS = 3;

// A term is fuzzed when it matched almost nothing, not only when it matched nothing.
// "asserties" occurs verbatim in exactly one unrelated note, which was enough to mark
// it "found" and suppress every expansion — so the note that spells it "assertie", the
// one actually being looked for, never got the credit. A term with a couple of hits in
// a 7000-note vault is a near-miss, not a hit.
const FUZZY_TRIGGER_MAX_FILES = 3;

const TOKEN_RE = /[\p{L}][\p{L}\p{N}_-]{2,29}/gu;

// Feed both content and path into the vocabulary — pass 1 matches terms against the
// path too, so a vocabulary built from content alone makes slug-only notes reachable
// exactly and unreachable fuzzily. Hyphenated tokens are added whole *and* split, so
// "assertions-that-cannot-fail.md" contributes "assertions" and "fail" as well
// as the full slug, while "continue-on-error" stays findable as one word.
function collectTokens(text: string, into: Set<string>): void {
  for (const m of text.matchAll(TOKEN_RE)) {
    into.add(m[0]);
    if (!m[0].includes("-")) continue;
    for (const part of m[0].split("-")) if (part.length >= 3) into.add(part);
  }
}

// Optimal string alignment distance: Levenshtein plus adjacent transposition as a
// single edit. Transposition is the most common typing error ("tokne" for "token"),
// and plain Levenshtein charges 2 for it — enough to push it past the threshold for
// exactly the medium-length words people mistype most. Bails out as soon as the whole
// row exceeds `max`, so the vocabulary scan stays cheap.
export function editDistance(a: string, b: string, max: number): number {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let prev2: number[] = [];
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  let curr: number[] = [];
  for (let i = 1; i <= a.length; i++) {
    curr = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let v = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        v = Math.min(v, prev2[j - 2] + 1);
      }
      curr[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    prev2 = prev;
    prev = curr;
  }
  return prev[b.length];
}

// Vocabulary tokens close enough to stand in for `term`, best first. `vocab` maps each
// token to the number of notes it appears in; that count is the tie-break, because
// distance alone picks badly. "tokne" is one edit from both "token" and "toke" — a
// deletion and a transposition — and ranking the tie by token length handed it "toke",
// a fragment occurring in zero notes as a word. Frequency settles it: the word people
// actually write is the word they meant.
export function expansionsFor(term: string, vocab: Map<string, number>): string[] {
  if (term.length < FUZZY_MIN_LEN) return [];
  const max = term.length >= 8 ? 2 : 1;
  const found: { token: string; d: number; freq: number }[] = [];
  for (const token of vocab.keys()) {
    // A typo almost never lands on the first character, and an inflection never does.
    // Requiring it cuts the vocabulary scan by roughly the size of the alphabet.
    if (token[0] !== term[0]) continue;
    if (Math.abs(token.length - term.length) > max) continue;
    // No "skip substring overlaps" guard here. It looks like a sensible way to avoid
    // re-finding what pass 1 already found, but half of it deletes the feature: when
    // the TERM contains the token ("asserties" ⊃ "assertie") that is the inflection
    // case, and pass 1 provably missed it — a substring search for the longer word
    // cannot find the shorter one. The other half is dead anyway: if a token contained
    // the term, the file content would have contained it too, and pass 1 would have
    // matched, so the term would never have reached this function.
    const d = editDistance(term, token, max);
    if (d > 0 && d <= max) found.push({ token, d, freq: vocab.get(token) ?? 0 });
  }
  found.sort((x, y) => x.d - y.d || y.freq - x.freq || x.token.localeCompare(y.token));
  return found.slice(0, FUZZY_MAX_EXPANSIONS).map((f) => f.token);
}

// Case-insensitive term search over path + content, ranked by how many of the
// query's terms a note contains.
//
// This used to be `content.indexOf(query)` — one literal substring match on the
// WHOLE query string. That cannot match two words which both occur but are not
// adjacent, so any descriptive multi-word query returned [] and read as "the note
// does not exist". Measured on the real vault: "assertions falen" returned nothing
// while both words sat in the same note. The failure was invisible to this file's
// tests because every one of them searched a single word.
//
// Ranking matters as much as matching: the old loop `break`-ed at `limit`, so it
// returned the first N notes in readdir order, not the best N. Score first, then
// truncate.
export async function search(query: string, limit = 20): Promise<Hit[]> {
  const q = query.toLowerCase().trim();
  const terms = [...new Set(q.split(/\s+/).filter(Boolean))];
  if (terms.length === 0) return [];

  interface Entry extends Hit {
    phrase: boolean;
    exact: number;
    fuzz: number;
    /** Terms this note matched verbatim — so pass 3 never pays a note twice for one term. */
    matchedTerms: Set<string>;
  }
  const entries = new Map<string, Entry>();
  const filesPerTerm = new Map<string, number>(terms.map((t) => [t, 0]));

  const scoreFile = (rel: string, content: string, matched: string[], isPhrase: boolean) => {
    const lower = content.toLowerCase();
    // Anchor the snippet on the most specific thing that matched: the full phrase if
    // present, else the longest matched term. Short common words ("de", "test") would
    // otherwise anchor it on a meaningless first occurrence.
    const anchor = isPhrase
      ? q
      : [...matched].sort((a, b) => b.length - a.length).find((t) => lower.includes(t));
    let snippet = "";
    if (anchor) {
      const idx = lower.indexOf(anchor);
      const start = Math.max(0, idx - 60);
      snippet = content.slice(start, start + MAX_SNIPPET).replace(/\s+/g, " ").trim();
    }
    return { path: rel, title: titleOf(content, rel), snippet };
  };

  // Pass 1 — exact terms. Deliberately does no tokenising: this is the pass every
  // query runs, and the fuzzy machinery must not tax it.
  for await (const f of mdFiles()) {
    const rel = relative(brainRoot(), f);
    const content = await readFile(f, "utf8");
    const lower = content.toLowerCase();
    const relLower = rel.toLowerCase();

    const matched = terms.filter((t) => lower.includes(t) || relLower.includes(t));
    for (const t of matched) filesPerTerm.set(t, (filesPerTerm.get(t) ?? 0) + 1);
    if (matched.length === 0) continue;

    // A note carrying the query verbatim outranks one that merely scatters the same
    // terms, so an exact-phrase search stays as precise as it was before.
    const phrase = terms.length > 1 && (lower.includes(q) || relLower.includes(q));
    entries.set(rel, {
      ...scoreFile(rel, content, matched, phrase),
      score: matched.length,
      exact: matched.length,
      fuzz: 0,
      phrase,
      matchedTerms: new Set(matched),
    });
  }

  const weak = terms.filter((t) => (filesPerTerm.get(t) ?? 0) < FUZZY_TRIGGER_MAX_FILES);
  if (weak.some((t) => t.length >= FUZZY_MIN_LEN)) {
    // Pass 2 — build the vocabulary, with a per-note frequency for each token.
    const vocab = new Map<string, number>();
    for await (const f of mdFiles()) {
      const rel = relative(brainRoot(), f);
      const content = await readFile(f, "utf8");
      const perFile = new Set<string>();
      collectTokens(content.toLowerCase(), perFile);
      collectTokens(rel.toLowerCase(), perFile);
      for (const t of perFile) vocab.set(t, (vocab.get(t) ?? 0) + 1);
    }

    const expansions = new Map<string, string[]>();
    for (const t of weak) {
      const e = expansionsFor(t, vocab);
      if (e.length) expansions.set(t, e);
    }

    // Pass 3 — credit notes that carry a substitute for a term the query got wrong.
    if (expansions.size > 0) {
      for await (const f of mdFiles()) {
        const rel = relative(brainRoot(), f);
        const content = await readFile(f, "utf8");
        const lower = content.toLowerCase();
        const relLower = rel.toLowerCase();
        const existing = entries.get(rel);

        const substitutions: string[] = [];
        const hitTokens: string[] = [];
        for (const [term, alts] of expansions) {
          // Already credited verbatim on this note — a term must not be paid twice.
          if (existing?.matchedTerms.has(term)) continue;
          const alt = alts.find((a) => lower.includes(a) || relLower.includes(a));
          if (alt) {
            substitutions.push(`${term}→${alt}`);
            hitTokens.push(alt);
          }
        }
        if (substitutions.length === 0) continue;

        if (existing) {
          existing.fuzz += substitutions.length;
          existing.score += substitutions.length * FUZZY_WEIGHT;
          existing.fuzzy = substitutions;
        } else {
          entries.set(rel, {
            ...scoreFile(rel, content, hitTokens, false),
            score: substitutions.length * FUZZY_WEIGHT,
            exact: 0,
            fuzz: substitutions.length,
            phrase: false,
            fuzzy: substitutions,
            matchedTerms: new Set(),
          });
        }
      }
    }
  }

  const scored = [...entries.values()];
  // Exact and fuzzy are separate ranking keys, not one blended number. Blending needs a
  // weight, and any weight is wrong at some term count: at 0.5, three fuzzy matches
  // (1.5) overtake one exact one (1.0). Sorting on exact first means no quantity of
  // guesses can ever displace a note that actually contains what was asked for.
  scored.sort(
    (a, b) =>
      Number(b.phrase) - Number(a.phrase) ||
      b.exact - a.exact ||
      b.fuzz - a.fuzz ||
      a.path.localeCompare(b.path), // stable, reproducible ordering within a tier
  );
  return scored.slice(0, limit).map(({ path, title, snippet, score, fuzzy }) =>
    fuzzy ? { path, title, snippet, score, fuzzy } : { path, title, snippet, score },
  );
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
