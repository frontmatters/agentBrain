import test, { after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Fixture vault (never the real brain): one open note + two sealed space probes,
// all carrying the same unique token so a single query would match all three unless
// spaces are filtered out of enumeration. __probe__ is the one we activate in the
// active-space tests; __other__ stays sealed to prove only the active space opens.
const root = mkdtempSync(join(tmpdir(), "ab-mcp-spaces-"));
const TOKEN = "zzspaceprobe" + Math.random().toString(36).slice(2, 10);
mkdirSync(join(root, "local", "learnings"), { recursive: true });
mkdirSync(join(root, "local", "spaces", "__probe__"), { recursive: true });
mkdirSync(join(root, "local", "spaces", "__other__"), { recursive: true });
writeFileSync(
  join(root, "local", "learnings", "open.md"),
  `---\ntitle: Open Note\n---\n\nOpen knowledge ${TOKEN}.\n`,
);
writeFileSync(
  join(root, "local", "spaces", "__probe__", "x.md"),
  `---\ntitle: Sealed Probe\n---\n\nSealed owner secret ${TOKEN}.\n`,
);
writeFileSync(
  join(root, "local", "spaces", "__other__", "y.md"),
  `---\ntitle: Other Space\n---\n\nOther owner secret ${TOKEN}.\n`,
);

after(() => {
  delete process.env.AGENTBRAIN_SPACE;
  delete process.env.AGENTBRAIN_CONTEXT;
  rmSync(root, { recursive: true, force: true });
});

test("search does not surface local/spaces/ notes", async () => {
  process.env.AGENTBRAIN_DIR = root;
  delete process.env.AGENTBRAIN_SPACE;
  const { search } = await import("../search");
  const hits = await search(TOKEN);
  assert.ok(hits.length >= 1, "expected the open note to be found");
  assert.ok(
    hits.every((h) => !h.path.includes("/spaces/")),
    `search must not surface local/spaces/ notes; got ${JSON.stringify(hits.map((h) => h.path))}`,
  );
});

test("recent does not surface local/spaces/ notes", async () => {
  process.env.AGENTBRAIN_DIR = root;
  delete process.env.AGENTBRAIN_SPACE;
  const { recent } = await import("../search");
  const r = await recent(50);
  assert.ok(
    r.every((n) => !n.path.includes("/spaces/")),
    `recent must not surface local/spaces/ notes; got ${JSON.stringify(r.map((n) => n.path))}`,
  );
});

test("Phase 1: explicit brain_read of a space path still returns content", async () => {
  process.env.AGENTBRAIN_DIR = root;
  const { read } = await import("../search");
  const content = await read("local/spaces/__probe__/x.md");
  assert.match(content, /Sealed owner secret/);
});

test("Phase 3: active space (AGENTBRAIN_SPACE) IS surfaced; other spaces stay sealed", async () => {
  process.env.AGENTBRAIN_DIR = root;
  process.env.AGENTBRAIN_SPACE = "__probe__";
  try {
    const { search } = await import("../search");
    const paths = (await search(TOKEN)).map((h) => h.path);
    assert.ok(
      paths.some((p) => p.includes("/spaces/__probe__/")),
      `active space note must be surfaced; got ${JSON.stringify(paths)}`,
    );
    assert.ok(
      paths.every((p) => !p.includes("/spaces/__other__/")),
      `non-active spaces must stay sealed; got ${JSON.stringify(paths)}`,
    );
  } finally {
    delete process.env.AGENTBRAIN_SPACE;
  }
});

test("Phase 3: without an active space, no space note is surfaced", async () => {
  process.env.AGENTBRAIN_DIR = root;
  delete process.env.AGENTBRAIN_SPACE;
  const { search } = await import("../search");
  const hits = await search(TOKEN);
  assert.ok(hits.length >= 1, "expected the open note to be found");
  assert.ok(
    hits.every((h) => !h.path.includes("/spaces/")),
    `no space should be surfaced without an active space; got ${JSON.stringify(hits.map((h) => h.path))}`,
  );
});

test("active space resolved via AGENTBRAIN_CONTEXT IS surfaced", async () => {
  process.env.AGENTBRAIN_DIR = root;
  delete process.env.AGENTBRAIN_SPACE;
  process.env.AGENTBRAIN_CONTEXT = "__probe__";
  try {
    const { search } = await import("../search");
    const paths = (await search(TOKEN)).map((h) => h.path);
    assert.ok(
      paths.some((p) => p.includes("/spaces/__probe__/")),
      `AGENTBRAIN_CONTEXT space must be surfaced; got ${JSON.stringify(paths)}`,
    );
  } finally {
    delete process.env.AGENTBRAIN_CONTEXT;
  }
});

test("decommissioned: the .active-space marker is NOT honored for recall", async () => {
  process.env.AGENTBRAIN_DIR = root;
  delete process.env.AGENTBRAIN_SPACE;
  delete process.env.AGENTBRAIN_CONTEXT;
  writeFileSync(join(root, "local", ".active-space"), "__probe__\n");
  try {
    const { search } = await import("../search");
    const paths = (await search(TOKEN)).map((h) => h.path);
    assert.ok(
      paths.every((p) => !p.includes("/spaces/")),
      `the vault-global marker must NOT open a space (decommissioned); got ${JSON.stringify(paths)}`,
    );
  } finally {
    rmSync(join(root, "local", ".active-space"), { force: true });
  }
});
