import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = mkdtempSync(join(tmpdir(), "ab-mcp-search-"));
mkdirSync(join(root, "local", "learnings"), { recursive: true });
mkdirSync(join(root, "system"), { recursive: true });
writeFileSync(join(root, "local", "learnings", "dock.md"), "---\ntitle: Docking\n---\n\nAbout banana boats.\n");
writeFileSync(join(root, "system", "rules.md"), "# Rules\nPublic HOW/WHERE.\n");
writeFileSync(join(root, "system", "skills.md"), "# Skills\nindex.\n");
process.env.AGENTBRAIN_DIR = root;

test("search finds a content hit with title + snippet", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("banana");
  assert.equal(hits.length, 1);
  assert.equal(hits[0].path, "local/learnings/dock.md");
  assert.equal(hits[0].title, "Docking");
  assert.match(hits[0].snippet, /banana boats/);
});

// Every other search assertion here uses a single word, which is exactly why the
// substring bug survived: `indexOf(query)` over the whole query string cannot match
// two words that both occur but are not adjacent, and a single-word test never
// exercises that path. These notes are written so the terms are deliberately far
// apart in the text.
writeFileSync(
  join(root, "local", "learnings", "harbour.md"),
  "---\ntitle: Harbour\n---\n\nA crane lifts containers.\n\nLater the pilot boards the vessel.\n",
);
writeFileSync(
  join(root, "local", "learnings", "airfield.md"),
  "---\ntitle: Airfield\n---\n\nThe pilot files a flight plan.\n",
);

test("search matches terms that are not adjacent, and ranks by how many matched", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("crane pilot");
  assert.equal(hits.length, 2, "both notes contain at least one term");
  assert.equal(hits[0].path, "local/learnings/harbour.md", "2-term note ranks above 1-term note");
  assert.equal(hits[0].score, 2);
  assert.equal(hits[1].path, "local/learnings/airfield.md");
  assert.equal(hits[1].score, 1);
  assert.match(hits[0].snippet, /crane/);
});

// Scores the same 2/2 as airfield.md on "flight plan", but never as a phrase. Its name sorts
// BEFORE airfield.md on purpose: with an alphabetically later name the tie-break on path
// handed airfield.md the top slot anyway, so the assertion passed without the phrase bonus
// doing any work. Only the phrase may separate these two.
writeFileSync(
  join(root, "local", "learnings", "aerodrome-ops.md"),
  "---\ntitle: Aerodrome ops\n---\n\nThe plan is agreed.\n\nEvery flight is logged separately.\n",
);

test("search ranks an exact phrase above a same-score term scatter", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("flight plan");
  assert.equal(hits.length, 2, "both notes contain both terms");
  assert.equal(hits[0].score, hits[1].score, "…at the same score, so only the phrase separates them");
  assert.equal(hits[0].path, "local/learnings/airfield.md");
  assert.match(hits[0].snippet, /flight plan/);
});

// "the" appears early and often, "transponder" once and late — far enough apart that a
// snippet anchored on the wrong one cannot accidentally contain the other.
writeFileSync(
  join(root, "local", "learnings", "signals.md"),
  `---\ntitle: Signals\n---\n\nThe mast is tall. The rope is long. The deck is wet.\n\n${"Filler sentence with no query terms in it. ".repeat(8)}\n\nA transponder broadcasts.\n`,
);

test("the snippet anchors on the most specific matched term, not the first one", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("the transponder");
  const signals = hits.find((h) => h.path === "local/learnings/signals.md");
  assert.ok(signals, "note matches both terms");
  assert.match(signals.snippet, /transponder/, "anchored on the long, specific term");
  assert.doesNotMatch(signals.snippet, /The mast/, "not on the first hit of the common term");
});

// The filename term appears nowhere in the body or the frontmatter title, so this
// really is a path-only hit. (A first version of this test used a note whose title
// repeated the slug — it asserted "path-only" while actually matching on content.)
writeFileSync(
  join(root, "local", "learnings", "quayside.md"),
  "---\ntitle: Mooring\n---\n\nRopes and bollards.\n",
);

test("a path-only match still scores, with an empty snippet", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("quayside");
  assert.equal(hits.length, 1);
  assert.equal(hits[0].path, "local/learnings/quayside.md");
  assert.equal(hits[0].score, 1);
  assert.equal(hits[0].snippet, "", "term is in the path, not the content");
});

// Recall-noise skiplist. Named so it sorts BEFORE every real note: at equal score the
// tie-break is path order, so a dot-directory wins every tie. That is exactly how
// deleted notes reached rank 1 on the live vault, and it means a test that merely
// checked "the real note is somewhere in the results" would pass while the bug bites.
mkdirSync(join(root, "local", ".trash", "forget", "20260611-094359"), { recursive: true });
writeFileSync(
  join(root, "local", ".trash", "forget", "20260611-094359", "old.md"),
  "---\ntitle: Discarded\n---\n\nThe crane was sold.\n",
);
mkdirSync(join(root, "local", "graphify-out"), { recursive: true });
writeFileSync(join(root, "local", "graphify-out", "GRAPH_REPORT.md"), "# Graph\ncrane nodes: 4\n");

test("deleted, quarantined and machine-generated areas are skipped by default", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search, isSkipped } = await import("../search");
  const hits = await search("crane");
  assert.ok(hits.length > 0, "the real note still matches");
  assert.ok(
    hits.every((h) => !h.path.startsWith("local/.trash/")),
    `deleted notes must not rank; got ${JSON.stringify(hits.map((h) => h.path))}`,
  );
  assert.ok(hits.every((h) => !h.path.startsWith("local/graphify-out/")));
  assert.equal(isSkipped("local/.trash/forget/x/old.md"), true);
  assert.equal(isSkipped("local/learnings/harbour.md"), false);
});

test(".searchignore adds prefixes and '!' re-admits a default", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { skipPrefixes, isSkipped } = await import("../search");
  writeFileSync(
    join(root, "local", ".searchignore"),
    "# comment\n\nlocal/archive/\n!local/graphify-out/\n",
  );
  const p = skipPrefixes();
  assert.ok(p.includes("local/archive/"), "added prefix");
  assert.ok(!p.includes("local/graphify-out/"), "'!' removed a default");
  assert.ok(p.includes("local/.trash/"), "untouched default survives");
  assert.equal(isSkipped("local/archive/2023/chat.md", p), true);
  assert.equal(isSkipped("local/graphify-out/GRAPH_REPORT.md", p), false);
  rmSync(join(root, "local", ".searchignore"));
});

// Fuzzy recall. The three real-vault failure classes, each with a note that only a
// fuzzy match can reach: a transposed typo, a Dutch plural, and a term long enough
// to warrant distance 2.
writeFileSync(
  join(root, "local", "learnings", "credentials.md"),
  "---\ntitle: Credentials\n---\n\nRotate the token every quarter.\n",
);
writeFileSync(
  join(root, "local", "learnings", "verification.md"),
  "---\ntitle: Verification\n---\n\nEvery assertie must be mutated before you trust it.\n",
);

test("a transposed typo still finds the note, at a discounted score", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("tokne");
  const hit = hits.find((h) => h.path === "local/learnings/credentials.md");
  assert.ok(hit, "'tokne' reaches 'token' — transposition is the most common typo");
  assert.ok(hit.score < 1, `fuzzy match must score below an exact one, got ${hit.score}`);
  assert.deepEqual(hit.fuzzy, ["tokne→token"], "the substitution is reported, not silent");
});

// Mentions the plural once, and nothing else of interest. On the live vault exactly
// this existed: "asserties" occurred verbatim in one unrelated note, which marked the
// term "found" and suppressed every expansion — so the note spelling it "assertie",
// the one being looked for, got no credit at all. A near-miss must still fuzz.
writeFileSync(
  join(root, "local", "learnings", "decoy.md"),
  "---\ntitle: Decoy\n---\n\nSome asserties were discussed.\n",
);

test("a Dutch plural finds the singular, even when the plural also exists somewhere", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("asserties");
  const paths = hits.map((h) => h.path);
  const fuzzy = hits.find((h) => h.path === "local/learnings/verification.md");
  assert.ok(fuzzy, `an incidental verbatim hit must not suppress the expansion; got ${JSON.stringify(paths)}`);
  assert.deepEqual(fuzzy.fuzzy, ["asserties→assertie"]);
  // Not "decoy is #1" — both-forms.md carries the plural too and ties it at exact=1,
  // so which of the two sorts first says nothing. What must hold is that every
  // verbatim hit outranks the expansion.
  assert.ok(
    paths.indexOf("local/learnings/decoy.md") < paths.indexOf("local/learnings/verification.md"),
    `verbatim hits rank above the expansion; got ${JSON.stringify(paths)}`,
  );
});

// Holds both spellings. For the query "asserties" it matches verbatim AND contains the
// expansion, so without a guard it would be paid twice for one term and outrank notes
// that genuinely matched more of the query.
writeFileSync(
  join(root, "local", "learnings", "both-forms.md"),
  "---\ntitle: Both forms\n---\n\nOne assertie, many asserties.\n",
);

test("a term is never credited twice on the same note", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("asserties");
  const both = hits.find((h) => h.path === "local/learnings/both-forms.md");
  assert.ok(both);
  assert.equal(both.score, 1, "verbatim match only — the expansion is the same term");
  assert.equal(both.fuzzy, undefined);
});

// Two candidates one edit from "tokne": "token" (in two notes) and "toke" (in one).
// Distance cannot separate them — a deletion and a transposition both cost 1 — so the
// tie-break decides, and ranking it by token length picked the rare fragment.
writeFileSync(
  join(root, "local", "learnings", "sessions-note.md"),
  "---\ntitle: Sessions\n---\n\nThe token expires nightly.\n",
);
writeFileSync(
  join(root, "local", "learnings", "slang.md"),
  "---\ntitle: Slang\n---\n\nA toke is not a word we use.\n",
);

test("expansion prefers the word that actually occurs, not the shortest candidate", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("tokne");
  const hit = hits.find((h) => h.path === "local/learnings/credentials.md");
  assert.ok(hit);
  assert.deepEqual(hit.fuzzy, ["tokne→token"], "frequency settles the tie, not length");
});

// One note carries a single query term verbatim; the other carries three, all mistyped.
// Under a single blended score (1 exact = 1.0 vs 3 fuzzy = 1.5) the guesses win.
writeFileSync(
  join(root, "local", "learnings", "hangar.md"),
  "---\ntitle: Hangar\n---\n\nThe hangar doors are open.\n",
);
writeFileSync(
  join(root, "local", "learnings", "movements.md"),
  "---\ntitle: Movements\n---\n\nThe runway, the taxiway and the apron were resurfaced.\n",
);

test("no quantity of fuzzy matches can displace a single exact one", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("hangar runwya taxiwya aprno");
  assert.equal(hits[0].path, "local/learnings/hangar.md");
  const guessed = hits.find((h) => h.path === "local/learnings/movements.md");
  assert.ok(guessed, "the fuzzy note is still returned…");
  assert.ok(guessed.score > hits[0].score, "…and even outscores it on the blended number");
});

test("an exact match always outranks a fuzzy one", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  // 'quayside' exists verbatim in one path; 'quaysides' can only reach it fuzzily.
  // The exact note must not be displaced by anything the plural also brushes against.
  const exact = await search("quayside");
  const fuzzy = await search("quaysides");
  assert.equal(exact[0].path, "local/learnings/quayside.md");
  assert.equal(exact[0].score, 1);
  assert.ok(fuzzy[0].score < 1, "no exact term in the query means no full-score hit");
});

// Holds 'card', exactly one edit from 'cart'. Without a neighbour this close the
// length-floor test cannot fail: 'cart' would return nothing whatever the floor is,
// and lowering FUZZY_MIN_LEN left the suite green.
writeFileSync(
  join(root, "local", "learnings", "access.md"),
  "---\ntitle: Access\n---\n\nThe card opens the gate.\n",
);

test("short terms are never fuzzed", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  // 'cart' is one edit from 'card'. Below the length floor a typo is indistinguishable
  // from a different word, so fuzzing it buys noise rather than recall.
  const hits = await search("cart");
  assert.equal(hits.length, 0, `expected no hits, got ${JSON.stringify(hits.map((h) => h.path))}`);
});

test("one exact term and one typo combine on the same note", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  // The realistic shape of a mistyped query: most words land, one does not. The note
  // must collect both contributions rather than being scored by whichever pass saw it
  // first. (Only this case reaches the branch that upgrades an existing entry — with
  // the single-term tests alone, deleting that branch left the suite green.)
  const hits = await search("tokne rotate");
  const hit = hits.find((h) => h.path === "local/learnings/credentials.md");
  assert.ok(hit);
  assert.equal(hit.score, 1.5, "1 for the exact term + 0.5 for the fuzzy one");
  assert.deepEqual(hit.fuzzy, ["tokne→token"]);
});

test("read returns full content; rejects traversal", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { read } = await import("../search");
  assert.match(await read("system/rules.md"), /Public HOW\/WHERE/);
  await assert.rejects(() => read("../outside.md"), /escapes agentBrain root/);
});

test("recent returns notes newest-first", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { recent } = await import("../search");
  const r = await recent(2);
  assert.ok(r.length >= 1 && r.length <= 2);
  assert.ok("path" in r[0] && "mtime" in r[0]);
});

test("rules concatenates rules.md + skills.md", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { rules } = await import("../search");
  const out = await rules();
  assert.match(out, /Public HOW\/WHERE/);
  assert.match(out, /index\./);
});

test("MCP scope: security/biometric/config paths are excluded from search and read", async () => {
  process.env.AGENTBRAIN_DIR = root;
  mkdirSync(join(root, "local", "security"), { recursive: true });
  writeFileSync(join(root, "local", "security", "hardening.md"), "# Hardening\nbanana secret zone.\n");
  mkdirSync(join(root, "local", "addons", "voice", "voiceprint"), { recursive: true });
  writeFileSync(join(root, "local", "addons", "voice", "voiceprint", "profile.md"), "banana biometric\n");
  const { search, read, isExcluded } = await import("../search");

  const hits = await search("banana");
  assert.ok(hits.every((h) => !h.path.startsWith("local/security/")), "search must skip local/security/");
  assert.ok(hits.every((h) => !h.path.includes("/voiceprint/")), "search must skip voiceprints");

  await assert.rejects(() => read("local/security/hardening.md"), /outside MCP scope/);
  await assert.rejects(() => read("local/addons/voice/voiceprint/profile.json"), /outside MCP scope/);
  await assert.rejects(() => read("local/addons/weekly-review/config.json"), /outside MCP scope/);

  assert.equal(isExcluded("local/security/notes.md"), true);
  assert.equal(isExcluded("local/addons/voice/.consent"), true);
  assert.equal(isExcluded("local/learnings/dock.md"), false);
  assert.equal(isExcluded("system/rules.md"), false);
});
