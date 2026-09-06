import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// A checkout whose vault link is vault/ and that has no local/ at all: the
// alias is on its way out. Disk access follows vault/, identity stays local/.
const root = mkdtempSync(join(tmpdir(), "ab-mcp-vaultdir-"));
mkdirSync(join(root, "vault", "learnings"), { recursive: true });
mkdirSync(join(root, "system"), { recursive: true });
writeFileSync(join(root, "vault", "learnings", "kelp.md"), "---\ntitle: Kelp\n---\n\nAbout kelp forests.\n");
writeFileSync(join(root, "system", "rules.md"), "# Rules\n");
writeFileSync(join(root, "system", "skills.md"), "# Skills\n");

test("a vault/ directory without local/ is searched under the local/ identity", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { search } = await import("../search");
  const hits = await search("kelp");
  assert.equal(hits.length, 1);
  assert.equal(hits[0].path, "local/learnings/kelp.md");
  assert.equal(existsSync(join(root, "local")), false);
});

test("read resolves local/ and vault/ spellings to the same file on disk", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { read } = await import("../search");
  const { canonRel } = await import("../brain");
  assert.match(await read("local/learnings/kelp.md"), /kelp forests/);
  assert.match(await read(canonRel("vault/learnings/kelp.md")), /kelp forests/);
});

test("the access index lives beside the notes and keys on local/", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { recordAccess } = await import("../access");
  recordAccess("local/learnings/kelp.md");
  const idx = JSON.parse(readFileSync(join(root, "vault", ".access-index.json"), "utf8"));
  assert.ok("local/learnings/kelp.md" in idx, Object.keys(idx).join(","));
});
