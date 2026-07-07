import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = mkdtempSync(join(tmpdir(), "ab-mcp-write-"));
writeFileSync(join(root, "brain.json"), JSON.stringify({ namespace: "e37d107c-934a-4626-806e-8da1b442c8e4" }));

test("saveLearning writes a kebab note under local/learnings with frontmatter + uuid5 id", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { saveLearning } = await import("../write");
  const rel = await saveLearning("My Great Finding!", "The body text.", ["mcp", "test"]);
  assert.equal(rel, "local/learnings/my-great-finding.md");
  const content = readFileSync(join(root, rel), "utf8");
  assert.match(content, /^type: learning$/m);
  assert.match(content, /^confidence: low$/m);
  assert.match(content, /^tags: \[mcp, test\]$/m);
  assert.match(content, /^id: [0-9a-f-]{36}$/m);
  assert.match(content, /# My Great Finding!/);
});

test("saveLearning refuses secrets and refuses to clobber", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { saveLearning } = await import("../write");
  await assert.rejects(() => saveLearning("creds", "my api_key is sk-123", []), /secret/i);
  await saveLearning("Dup Note", "first", []);
  await assert.rejects(() => saveLearning("Dup Note", "second", []), /exists/i);
});

test("saveLearning allows secret-looking words inside code fences but still blocks them in prose", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { saveLearning } = await import("../write");
  // documentation example inside a code fence should pass
  const body = "Use this header:\n```\nAuthorization: Bearer ${API_TOKEN}\n```\nNever hardcode it.";
  const rel = await saveLearning("Auth header example in code fence", body, ["test"]);
  assert.ok(rel.endsWith(".md"));
  // real secret in prose should still be blocked
  await assert.rejects(
    () => saveLearning("Prose secret", "my bearer token is FAKE_TOKEN_PLACEHOLDER", []),
    /secret/i,
  );
});

test("projectUpdate writes index.md or a named section under local/projects", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { projectUpdate } = await import("../write");
  const a = await projectUpdate("Cool Project", undefined, "overview");
  assert.equal(a, "local/projects/cool-project/index.md");
  const b = await projectUpdate("Cool Project", "Deploy Notes", "how to deploy");
  assert.equal(b, "local/projects/cool-project/deploy-notes.md");
  assert.ok(existsSync(join(root, a)) && existsSync(join(root, b)));
});

test("projectUpdate refuses a secret in the section heading", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { projectUpdate } = await import("../write");
  await assert.rejects(
    () => projectUpdate("Safe Name", "my api_key is sk-abcdefgh", "body"),
    /secret/i,
  );
});

test("incognito mode blocks both MCP write paths (the PreToolUse hook does not cover MCP tools)", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { saveLearning, projectUpdate } = await import("../write");
  const flag = join(root, "local", "sessions", ".incognito");
  mkdirSync(join(root, "local", "sessions"), { recursive: true });
  writeFileSync(flag, "incognito enabled\n");
  try {
    await assert.rejects(() => saveLearning("While Incognito", "should not persist", []), /incognito/i);
    await assert.rejects(() => projectUpdate("Incognito Project", undefined, "should not persist"), /incognito/i);
  } finally {
    rmSync(flag);
  }
  // flag removed -> writes work again
  assert.ok((await saveLearning("After Incognito Off", "now allowed", [])).endsWith(".md"));
});
