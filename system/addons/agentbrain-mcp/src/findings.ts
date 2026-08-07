// findings.ts — read structured detector findings from local/findings/<detector>.json.
//
// Each detector (e.g. check-local-content, doctor, brain-review) emits a JSON file with shape:
//   { detector: string, last_run: ISO8601, findings: Finding[] }
// This module exposes a read-only surface for the MCP tool brain_findings_list.
// Captures + auto-close logic live in the detectors themselves (or a capture wrapper) —
// this module never writes.

import { existsSync } from "node:fs";
import { readFile, readdir } from "node:fs/promises";
import { brainPath } from "./brain";

export type Severity = "error" | "warning" | "info" | "opportunity";
export type FindingStatus = "open" | "auto_closed";

export interface Finding {
  id: string;
  severity: Severity;
  file?: string;
  kind?: string;
  message: string;
  suggested_action?: string;
  first_seen?: string;
  last_seen?: string;
  status?: FindingStatus;
}

export interface ListFindingsOptions {
  detector?: string;
  severity?: Severity | string;
  status?: FindingStatus | string;
}

export interface ListFindingsResult {
  detectors: string[];
  findings: Finding[];
}

// Sanitize a detector name into a safe filename component (no path traversal).
function sanitizeDetectorName(name: string): string {
  return name.replace(/[^a-zA-Z0-9_-]/g, "");
}

// List findings from local/findings/*.json, optionally filtered by detector / severity / status.
// Returns aggregated findings when no detector specified; empty result if findings dir absent.
export async function listFindings(opts: ListFindingsOptions = {}): Promise<ListFindingsResult> {
  let findingsDir: string;
  try {
    findingsDir = brainPath("local", "findings");
  } catch {
    return { detectors: [], findings: [] };
  }

  if (!existsSync(findingsDir)) {
    return { detectors: [], findings: [] };
  }

  let files: string[];
  if (opts.detector) {
    const safe = sanitizeDetectorName(opts.detector);
    if (!safe) return { detectors: [], findings: [] };
    files = [`${safe}.json`];
  } else {
    files = (await readdir(findingsDir)).filter((f) => f.endsWith(".json"));
  }

  const detectors: string[] = [];
  const findings: Finding[] = [];

  for (const file of files) {
    let path: string;
    try {
      path = brainPath("local", "findings", file);
    } catch {
      continue;
    }
    if (!existsSync(path)) continue;

    let data: { detector?: string; findings?: Finding[] };
    try {
      data = JSON.parse(await readFile(path, "utf8"));
    } catch {
      continue; // malformed JSON: skip, don't crash
    }

    const detName = data.detector ?? file.replace(/\.json$/, "");
    detectors.push(detName);

    for (const f of data.findings ?? []) {
      if (opts.severity && f.severity !== opts.severity) continue;
      // Status defaults to "open" if absent — auto-close mechanism flips it to "auto_closed".
      const status: FindingStatus = (f.status as FindingStatus) ?? "open";
      if (opts.status && status !== opts.status) continue;
      findings.push({ ...f, status });
    }
  }

  return { detectors, findings };
}
