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
