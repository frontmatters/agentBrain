import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = mkdtempSync(join(tmpdir(), "ab-mcp-access-"));
mkdirSync(join(root, "local", "learnings"), { recursive: true });
process.env.AGENTBRAIN_DIR = root;

test("accessWeight halves every 90 days and is 0 for a missing record", async () => {
  const { accessWeight } = await import("../access");
  const now = new Date("2026-08-16T00:00:00Z");
  assert.equal(accessWeight({ count: 10, last: "2026-08-16" }, now), 10); // 0 days
  assert.equal(accessWeight({ count: 10, last: "2026-05-18" }, now), 5);  // exactly 90 days
  assert.equal(accessWeight({ count: 10, last: "2026-02-17" }, now), 2.5); // 180 days
  assert.equal(accessWeight(undefined, now), 0);
});

test("recordAccess creates then increments a record with today's date", async () => {
  const { recordAccess, loadAccessIndex } = await import("../access");
  const now = new Date("2026-08-16T12:00:00Z");
  recordAccess("local/learnings/foo.md", now);
  assert.deepEqual(loadAccessIndex()["local/learnings/foo.md"], { count: 1, last: "2026-08-16" });
  recordAccess("local/learnings/foo.md", now);
  assert.equal(loadAccessIndex()["local/learnings/foo.md"].count, 2);
});

test("loadAccessIndex returns {} for a malformed sidecar, without throwing", async () => {
  writeFileSync(join(root, "local", ".access-index.json"), "{ not json");
  const { loadAccessIndex } = await import("../access");
  assert.deepEqual(loadAccessIndex(), {});
});

test("recordAccess canonicalizes the key to search's relative form", async () => {
  const { recordAccess, loadAccessIndex } = await import("../access");
  const now = new Date("2026-08-16T00:00:00Z");
  recordAccess("./local/learnings/canon.md", now);   // non-canonical input
  recordAccess("local/learnings/canon.md", now);      // canonical input → same key
  const idx = loadAccessIndex();
  assert.equal(idx["local/learnings/canon.md"]?.count, 2, "both spellings hit one canonical key");
  assert.equal(idx["./local/learnings/canon.md"], undefined, "no raw-path key leaked");
});
