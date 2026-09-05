import { readFileSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { brainRoot, brainPath, localDisk, brainRel } from "./brain";

// One named knob (spec open question 1): trivially tunable after real use.
const HALFLIFE_DAYS = 90;
const MS_PER_DAY = 86_400_000;

export interface AccessRecord { count: number; last: string; } // last = YYYY-MM-DD
export type AccessIndex = Record<string, AccessRecord>;

// Gitignored sidecar, dot-prefixed in local/ like .parks-index.json / .space-map.json.
function indexPath(): string {
  return join(localDisk(), ".access-index.json");
}

// A runtime cache, never a hard dependency: absent OR malformed → empty, no throw.
export function loadAccessIndex(): AccessIndex {
  try {
    const parsed = JSON.parse(readFileSync(indexPath(), "utf8"));
    return parsed && typeof parsed === "object" ? (parsed as AccessIndex) : {};
  } catch {
    return {};
  }
}

function isoDay(now: Date): string {
  return now.toISOString().slice(0, 10);
}

// Best-effort read-modify-write of the whole index (spec open question 2: fine for a
// single-user vault; swap to an append log if concurrent loss ever bites).
export function recordAccess(relPath: string, now = new Date()): void {
  const key = brainRel(brainPath(relPath)); // same form search() keys on
  const idx = loadAccessIndex();
  const prev = idx[key];
  idx[key] = { count: (prev?.count ?? 0) + 1, last: isoDay(now) };
  writeFileSync(indexPath(), `${JSON.stringify(idx, null, 2)}\n`);
}

// Recency-decayed use: count × 0.5^(daysSinceLast / HALFLIFE_DAYS).
export function accessWeight(rec: AccessRecord | undefined, now = new Date()): number {
  if (!rec) return 0;
  const last = Date.parse(rec.last);
  if (Number.isNaN(last)) return 0;
  const days = Math.max(0, (now.getTime() - last) / MS_PER_DAY);
  return rec.count * Math.pow(0.5, days / HALFLIFE_DAYS);
}
