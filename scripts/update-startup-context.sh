#!/usr/bin/env bash
# update-startup-context.sh — aggregate local/findings/*.json into one concise
# markdown summary at local/sessions/startup-context.md. This is the SURFACE step
# (§3) of the self-improving-loop design: a single file every agent reads at
# session-start so it knows what's open in the brain without consuming the full
# findings JSON in the system prompt.
#
# Usage:
#   bash scripts/update-startup-context.sh
#
# Output: short markdown (target <30 lines, <500 chars) with aggregated counts
# per detector + per severity. Pointer to brain_findings_list for details.
#
# Exit codes:
#   0 — wrote (or no-op if nothing to surface)
#   1 — write failure

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FINDINGS_DIR="$ROOT_DIR/local/findings"
OUT_FILE="$ROOT_DIR/local/sessions/startup-context.md"
TMP_FILE="${OUT_FILE}.tmp.$$"

mkdir -p "$(dirname "$OUT_FILE")"

python3 - "$FINDINGS_DIR" "$OUT_FILE" "$TMP_FILE" "$ROOT_DIR" <<'PY'
import json, os, glob, sys
from datetime import datetime, timezone
from collections import Counter

findings_dir, out_file, tmp_file, root_dir = sys.argv[1:5]

generated = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

files = sorted(glob.glob(os.path.join(findings_dir, "*.json"))) if os.path.isdir(findings_dir) else []

open_by_det = Counter()
open_by_sev = Counter()
auto_closed_by_det = Counter()
total_open = 0
total_closed = 0

for f in files:
    try:
        d = json.load(open(f))
    except (json.JSONDecodeError, OSError):
        continue
    det = d.get("detector") or os.path.basename(f).replace(".json", "")
    for finding in d.get("findings", []):
        status = finding.get("status", "open")
        sev = finding.get("severity", "unknown")
        if status == "open":
            total_open += 1
            open_by_det[det] += 1
            open_by_sev[sev] += 1
        elif status == "auto_closed":
            total_closed += 1
            auto_closed_by_det[det] += 1

# Compose the markdown — brief, scannable, no per-finding noise.
lines = []
lines.append("# agentBrain — session-start status")
lines.append("")
lines.append(f"Generated: {generated}")
lines.append("")

if total_open == 0 and total_closed == 0:
    lines.append("No findings tracked yet — `local/findings/` is empty.")
    lines.append("Run `bash scripts/capture-findings.sh <detector>` to populate.")
else:
    if total_open > 0:
        sev_summary = ", ".join(f"{c} {s}" for s, c in sorted(open_by_sev.items()))
        lines.append(f"**Open findings**: {total_open} ({sev_summary})")
        for det, n in sorted(open_by_det.items(), key=lambda x: -x[1]):
            lines.append(f"- {det}: {n}")
        lines.append("")
    if total_closed > 0:
        lines.append(f"**Auto-closed** (resolved since last run): {total_closed}")
        for det, n in sorted(auto_closed_by_det.items(), key=lambda x: -x[1]):
            lines.append(f"- {det}: {n}")
        lines.append("")
    lines.append("For details: call MCP tool `brain_findings_list(detector?, severity?, status?)`")
    lines.append("or read `local/findings/<detector>.json` directly.")
    if total_open > 0:
        lines.append("Actionable triage list: `local/backlog/auto-findings-triage.md` (regenerated each tick).")

content = "\n".join(lines) + "\n"
with open(tmp_file, "w") as f:
    f.write(content)

print(f"update-startup-context: {total_open} open, {total_closed} auto_closed across {len(files)} detector(s) → {os.path.relpath(out_file, root_dir)}")
PY

mv "$TMP_FILE" "$OUT_FILE"
