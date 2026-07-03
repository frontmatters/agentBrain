import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// Repo root is 5 levels up: tests -> src -> agentbrain-mcp -> addons -> system -> root.
const ROOT = join(import.meta.dir, "..", "..", "..", "..", "..");

test("noteId matches scripts/uuid5-gen.sh for a known path", async () => {
  const { noteId } = await import("../uuid5");
  const ns = JSON.parse(readFileSync(join(ROOT, "brain.json"), "utf8")).namespace as string;
  const expected = execFileSync("bash", [join(ROOT, "scripts/uuid5-gen.sh"), "learnings/Docker"], {
    encoding: "utf8",
  }).trim();
  assert.equal(noteId(ns, "learnings/Docker"), expected);
});

test("uuid5 sets version 5 and RFC4122 variant", async () => {
  const { uuid5 } = await import("../uuid5");
  const id = uuid5("e37d107c-934a-4626-806e-8da1b442c8e4", "agentBrain/x");
  assert.equal(id[14], "5");                       // version nibble
  assert.match(id[19], /[89ab]/);                  // variant nibble
});
