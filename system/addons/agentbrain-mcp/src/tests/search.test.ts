import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
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
