import test from "node:test";
import assert from "node:assert/strict";

const ROOT = "/tmp/ab-mcp-test";

test("brainRoot resolves to AGENTBRAIN_DIR", async () => {
  process.env.AGENTBRAIN_DIR = ROOT;
  const { brainRoot, brainPath } = await import("../brain");
  assert.equal(brainRoot(), ROOT);
  assert.equal(brainPath("system", "rules.md"), `${ROOT}/system/rules.md`);
});

test("brainRoot honors AGENTBRAIN_HOME (bash semantics: <home>/agentBrain) when AGENTBRAIN_DIR is unset", async () => {
  delete process.env.AGENTBRAIN_DIR;
  process.env.AGENTBRAIN_HOME = "/tmp/ab-home";
  const { brainRoot } = await import("../brain");
  assert.equal(brainRoot(), "/tmp/ab-home/agentBrain");
  delete process.env.AGENTBRAIN_HOME;
});

test("AGENTBRAIN_DIR wins over AGENTBRAIN_HOME", async () => {
  process.env.AGENTBRAIN_DIR = ROOT;
  process.env.AGENTBRAIN_HOME = "/tmp/should-be-ignored";
  const { brainRoot } = await import("../brain");
  assert.equal(brainRoot(), ROOT);
  delete process.env.AGENTBRAIN_HOME;
});

test("configured external vault is accepted by brainPath", async () => {
  process.env.AGENTBRAIN_DIR = ROOT;
  process.env.AGENTBRAIN_VAULT = "/tmp/ab-user-vault";
  const { vaultDir, brainPath } = await import("../brain");
  assert.equal(vaultDir(), "/tmp/ab-user-vault");
  assert.equal(
    brainPath("vault", "learnings", "patterns.md"),
    "/tmp/ab-user-vault/learnings/patterns.md",
  );
  assert.equal(
    brainPath("local", "projects", "demo", "index.md"),
    "/tmp/ab-user-vault/projects/demo/index.md",
  );
  delete process.env.AGENTBRAIN_VAULT;
});

test("brainPath rejects traversal outside the brain", async () => {
  process.env.AGENTBRAIN_DIR = ROOT;
  const { brainPath } = await import("../brain");
  assert.throws(() => brainPath("..", "outside.md"), /escapes agentBrain root/);
  assert.throws(() => brainPath("/etc/passwd"), /escapes agentBrain root/);
});

test("localPath confines writes to local/", async () => {
  process.env.AGENTBRAIN_DIR = ROOT;
  const { localPath } = await import("../brain");
  assert.equal(localPath("learnings", "x.md"), `${ROOT}/local/learnings/x.md`);
  assert.throws(() => localPath("..", "system", "rules.md"), /under local\//);
});

// vault/ and local/ name one note: the API folds the new spelling to the one every id uses.
import { canonRel } from "../brain";
test("canonRel folds a leading vault/ to local/", () => {
  assert.equal(canonRel("vault/learnings/x.md"), "local/learnings/x.md");
  assert.equal(canonRel("local/learnings/x.md"), "local/learnings/x.md");
  assert.equal(canonRel("local/projects/vault/notes.md"), "local/projects/vault/notes.md");
  assert.equal(canonRel("vault"), "local");
});
