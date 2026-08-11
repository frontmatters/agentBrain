import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = mkdtempSync(join(tmpdir(), "ab-mcp-findings-"));
mkdirSync(join(root, "local", "findings"), { recursive: true });

const checkLocalContent = {
  detector: "check-local-content",
  last_run: "2026-05-24T00:00:00Z",
  findings: [
    {
      id: "check-local-content:dead-link:local/foo.md:bar",
      severity: "warning",
      file: "local/foo.md",
      kind: "dead-link",
      message: "dead wiki-link [[bar]]",
      first_seen: "2026-05-22T10:00:00Z",
      last_seen: "2026-05-24T00:00:00Z",
      status: "open",
    },
    {
      id: "check-local-content:missing-id:local/baz.md",
      severity: "error",
      file: "local/baz.md",
      kind: "missing-id",
      message: "missing id",
      first_seen: "2026-05-24T00:00:00Z",
      last_seen: "2026-05-24T00:00:00Z",
      status: "open",
    },
    {
      id: "check-local-content:dead-link:local/old.md:gone",
      severity: "warning",
      file: "local/old.md",
      kind: "dead-link",
      message: "dead wiki-link [[gone]]",
      first_seen: "2026-05-20T00:00:00Z",
      last_seen: "2026-05-23T00:00:00Z",
      status: "auto_closed",
    },
  ],
};

const doctor = {
  detector: "doctor",
  last_run: "2026-05-24T00:00:00Z",
  findings: [
    {
      id: "doctor:shellcheck:scripts/x.sh",
      severity: "error",
      file: "scripts/x.sh",
      kind: "shellcheck",
      message: "SC2086",
      status: "open",
    },
  ],
};

writeFileSync(
  join(root, "local", "findings", "check-local-content.json"),
  JSON.stringify(checkLocalContent),
);
writeFileSync(join(root, "local", "findings", "doctor.json"), JSON.stringify(doctor));
process.env.AGENTBRAIN_DIR = root;

test("listFindings returns all findings across detectors when unfiltered", async () => {
  const { listFindings } = await import("../findings");
  const { detectors, findings } = await listFindings();
  assert.equal(detectors.length, 2);
  assert.ok(detectors.includes("check-local-content"));
  assert.ok(detectors.includes("doctor"));
  assert.equal(findings.length, 4);
});

test("listFindings filters by detector", async () => {
  const { listFindings } = await import("../findings");
  const { detectors, findings } = await listFindings({ detector: "doctor" });
  assert.deepEqual(detectors, ["doctor"]);
  assert.equal(findings.length, 1);
  assert.equal(findings[0]?.id, "doctor:shellcheck:scripts/x.sh");
});

test("listFindings filters by severity", async () => {
  const { listFindings } = await import("../findings");
  const { findings } = await listFindings({ severity: "error" });
  assert.equal(findings.length, 2);
  assert.ok(findings.every((f) => f.severity === "error"));
});

test("listFindings filters by status", async () => {
  const { listFindings } = await import("../findings");
  const openOnly = await listFindings({ status: "open" });
  assert.equal(openOnly.findings.length, 3);
  const closedOnly = await listFindings({ status: "auto_closed" });
  assert.equal(closedOnly.findings.length, 1);
  assert.equal(closedOnly.findings[0]?.kind, "dead-link");
});

test("listFindings combines filters (detector + severity)", async () => {
  const { listFindings } = await import("../findings");
  const { findings } = await listFindings({
    detector: "check-local-content",
    severity: "warning",
  });
  assert.equal(findings.length, 2);
  assert.ok(findings.every((f) => f.severity === "warning"));
});

test("listFindings rejects detector names with path-traversal characters", async () => {
  const { listFindings } = await import("../findings");
  // ../etc → sanitized to "etc" → ".json" file likely absent → empty
  const { findings } = await listFindings({ detector: "../etc/passwd" });
  assert.equal(findings.length, 0);
});

test("listFindings returns empty when findings dir absent", async () => {
  const emptyRoot = mkdtempSync(join(tmpdir(), "ab-mcp-findings-empty-"));
  process.env.AGENTBRAIN_DIR = emptyRoot;
  const { listFindings } = await import("../findings");
  const { detectors, findings } = await listFindings();
  assert.equal(detectors.length, 0);
  assert.equal(findings.length, 0);
  rmSync(emptyRoot, { recursive: true });
  process.env.AGENTBRAIN_DIR = root; // restore for any later tests in same process
});

test("listFindings skips malformed JSON files without crashing", async () => {
  const garbledRoot = mkdtempSync(join(tmpdir(), "ab-mcp-findings-garbled-"));
  mkdirSync(join(garbledRoot, "local", "findings"), { recursive: true });
  writeFileSync(join(garbledRoot, "local", "findings", "broken.json"), "{not json");
  writeFileSync(
    join(garbledRoot, "local", "findings", "good.json"),
    JSON.stringify({ detector: "good", findings: [{ id: "g:1", severity: "info", message: "ok" }] }),
  );
  process.env.AGENTBRAIN_DIR = garbledRoot;
  const { listFindings } = await import("../findings");
  const { detectors, findings } = await listFindings();
  assert.equal(detectors.length, 1, "broken.json should be skipped");
  assert.equal(findings.length, 1);
  rmSync(garbledRoot, { recursive: true });
  process.env.AGENTBRAIN_DIR = root;
});
