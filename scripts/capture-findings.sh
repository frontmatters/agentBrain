#!/usr/bin/env bash
# capture-findings.sh — run a detector in --json mode, merge with previous findings,
# write to local/findings/<detector>.json with first_seen/last_seen tracking and
# auto-close diff. This is the CAPTURE step of the self-improving-loop design
# (local/backlog/2026-05-23-self-improving-loop-design.md).
#
# Usage:
#   bash scripts/capture-findings.sh <detector>
# Where <detector> is the script base name (no .sh), e.g. "check-local-content".
# The detector script must support a --json flag emitting:
#   { detector, run_at, findings: [{ id, severity, message, ... }] }
#
# Merge semantics (auto-close):
#   - Finding id in both prev + current → keep prev.first_seen, set last_seen = run_at, status=open
#   - Finding id new in current         → first_seen = last_seen = run_at, status=open
#   - Finding id gone from current      → preserve prev fields, set status=auto_closed
#                                         (first_seen + last_seen unchanged; this is the historical
#                                         resolution-point)
#
# Atomic write via tmp + rename. Detector failures (non-zero exit) preserve previous file.
#
# Exit codes:
#   0 — capture completed (any finding count, including zero)
#   1 — detector script itself failed (broken self-test, missing brain.json, malformed JSON)
#   2 — usage error

set -euo pipefail

if [ $# -ne 1 ]; then
	echo "Usage: $0 <detector>" >&2
	echo "  e.g. $0 check-local-content" >&2
	exit 2
fi

DETECTOR="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTOR_SCRIPT="${SCRIPT_DIR}/${DETECTOR}.sh"
if [ ! -x "$DETECTOR_SCRIPT" ]; then
	echo "capture-findings: detector script not found or not executable: $DETECTOR_SCRIPT" >&2
	exit 1
fi

ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FINDINGS_DIR="$ROOT_DIR/local/findings"
FINDINGS_FILE="$FINDINGS_DIR/${DETECTOR}.json"
TMP_FILE="${FINDINGS_FILE}.tmp.$$"
mkdir -p "$FINDINGS_DIR"

# Python does the merge work. Bash is just an orchestrator for paths/args + atomic rename.
python3 <<PY
import json, subprocess, sys, os
from datetime import datetime, timezone

detector = "$DETECTOR"
detector_script = "$DETECTOR_SCRIPT"
prev_file = "$FINDINGS_FILE"
tmp_file = "$TMP_FILE"

# Run the detector with --json. Detector failures (non-zero exit) abort capture to
# preserve the previous file — better stale than corrupted.
try:
    raw = subprocess.check_output(["bash", detector_script, "--json"])
except subprocess.CalledProcessError as e:
    print(f"capture-findings: detector {detector} exited {e.returncode}; previous findings preserved", file=sys.stderr)
    sys.exit(1)

current = json.loads(raw)
run_at = current.get("run_at") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

prev = {"findings": []}
if os.path.exists(prev_file):
    try:
        prev = json.load(open(prev_file))
    except (json.JSONDecodeError, OSError):
        # If previous file is corrupt, treat as no-previous. Don't silently lose state
        # for what may be the only thing keeping the loop honest, but don't crash either.
        print(f"capture-findings: previous {prev_file} unreadable; treating as fresh run", file=sys.stderr)
        prev = {"findings": []}

prev_by_id = {f["id"]: f for f in prev.get("findings", []) if "id" in f}
cur_by_id = {f["id"]: f for f in current.get("findings", []) if "id" in f}

merged = []
# Persisting + new findings: status=open in both cases, first_seen preserved if known.
for fid, f in cur_by_id.items():
    if fid in prev_by_id:
        p = prev_by_id[fid]
        f["first_seen"] = p.get("first_seen", run_at)
        f["last_seen"] = run_at
    else:
        f["first_seen"] = run_at
        f["last_seen"] = run_at
    f["status"] = "open"
    merged.append(f)

# Auto-closed: in previous but absent from current. Preserve historical timestamps;
# only flip status. If the issue regresses later, the next run sees it as "new" again
# (because we keep auto_closed in our state but it's not in the cur_by_id index above).
for fid, p in prev_by_id.items():
    if fid not in cur_by_id:
        p["status"] = "auto_closed"
        merged.append(p)

out = {
    "detector": current.get("detector", detector),
    "last_run": run_at,
    "findings": merged,
}

with open(tmp_file, "w") as f:
    json.dump(out, f, indent=2)
    f.write("\n")

# Brief summary to stdout (humans + log capture). Cron/launchd hosts can keep this.
open_count = sum(1 for f in merged if f.get("status") == "open")
closed_count = sum(1 for f in merged if f.get("status") == "auto_closed")
new_count = sum(1 for fid in cur_by_id if fid not in prev_by_id)
print(f"capture-findings: {detector} → {len(merged)} findings ({open_count} open, {closed_count} auto_closed, {new_count} new this run)")

# Append a metrics row to local/metrics/findings-history.jsonl (append-only).
# Phase 5 of the self-improving loop: makes loop-health measurable over time
# (declining open_count = working; rising = regressing). Each detector adds one
# row per run; JSONL keeps it concurrent-safe (line-atomic appends on POSIX).
metrics_dir = os.path.join(os.path.dirname(os.path.dirname(prev_file)), "metrics")
os.makedirs(metrics_dir, exist_ok=True)
metrics_file = os.path.join(metrics_dir, "findings-history.jsonl")
row = {
    "ts": run_at,
    "detector": detector,
    "open": open_count,
    "auto_closed": closed_count,
    "new": new_count,
    "total": len(merged),
}
with open(metrics_file, "a") as f:
    f.write(json.dumps(row) + "\n")
PY

# Atomic publish: rename only succeeds if write succeeded above.
mv "$TMP_FILE" "$FINDINGS_FILE"
