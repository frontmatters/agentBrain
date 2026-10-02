#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# update-startup-context.sh — aggregate vault/findings/*.json into one concise
# markdown summary at vault/sessions/startup-context.md. This is the SURFACE step
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

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck source=scripts/lib/vault.sh
. "$ROOT_DIR/scripts/lib/vault.sh"
FINDINGS_DIR="$VAULT_DIR/findings"
OUT_FILE="$VAULT_DIR/sessions/startup-context.md"
TMP_FILE="${OUT_FILE}.tmp.$$"

mkdir -p "$(dirname "$OUT_FILE")"

python3 - "$FINDINGS_DIR" "$OUT_FILE" "$TMP_FILE" "$ROOT_DIR" <<'PY'
import json, os, glob, sys, subprocess, shutil
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
# Independently inspect the installed command and links; never invoke brain here.
home = os.environ.get("AGENTBRAIN_HOME") or os.environ["HOME"]
cli_dirs = ([os.path.join(home, "bin"), os.path.join(home, ".local", "bin")]
            if home == os.environ["HOME"] else [os.path.join(home, "bin")])
checkout = os.path.join(home, "agentBrain")
brain_script = os.path.join(checkout, "scripts", "brain.sh")
if not os.path.isfile(brain_script):
    brain_script = os.path.join(root_dir, "scripts", "brain.sh")
issues = []
command = shutil.which("brain")
if not command or os.path.realpath(command) != os.path.realpath(brain_script) or not os.path.isfile(os.path.realpath(command)):
    dest = os.path.join(next((d for d in cli_dirs if os.path.isdir(d)), cli_dirs[0]), "brain")
    issues.append(f"- `brain` on PATH is missing or does not resolve to the active brain.sh. Fix: `ln -sfn {brain_script} {dest}` (ensure {os.path.dirname(dest)} is on PATH).")
for directory in cli_dirs:
    if not os.path.isdir(directory):
        continue
    for link in sorted(glob.glob(os.path.join(directory, "*"))):
        if not os.path.islink(link):
            continue
        target = os.readlink(link)
        absolute = os.path.abspath(os.path.join(directory, target))
        # Include historical checkout paths as well as the stable alias/vault.
        if not any(part.startswith("agentBrain") for part in absolute.split(os.sep)):
            continue
        if os.path.exists(link):
            continue
        replacement = ""
        for marker in ("/scripts/", "/system/", "/vault/"):
            if marker in absolute:
                replacement = os.path.join(checkout, marker.strip("/"), absolute.split(marker, 1)[1])
                break
        if not replacement and os.path.basename(link) in ("brain", "agentbrain"):
            replacement = brain_script
        if replacement and os.path.isfile(replacement):
            fix = f"Fix: `ln -sfn {replacement} {link}`."
        else:
            fix = "Restore the missing target before relinking; no replacement exists in the active checkout."
        issues.append(f"- Broken CLI link `{link}` -> `{target}`. {fix}")
if issues:
    lines.extend(["## Broken brain commands and links", "Mention these to the owner before anything else:", *issues, ""])
# Read from the queue, not from a second reminder store. The list is sorted by due date.
try:
    reminders = subprocess.check_output(["bash", os.path.join(root_dir, "scripts/remind.sh"), "list", "--plain"], text=True).splitlines()
except (OSError, subprocess.CalledProcessError):
    reminders = []
# Local date: a reminder "on" a day is due from local midnight, not UTC midnight.
today = datetime.now().date().isoformat()
due = [row for row in reminders if row[:10] <= today]
if due:
    lines.extend(["## Reminders due", "Mention these to the owner before anything else:"])
    lines.extend(f"- {row}" for row in due)
    lines.append("")
lines.append(f"Generated: {generated}")
lines.append("")

if total_open == 0 and total_closed == 0:
    lines.append("No findings tracked yet — `vault/findings/` is empty.")
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
    lines.append("or read `vault/findings/<detector>.json` directly.")
    if total_open > 0:
        lines.append("Actionable triage list: `vault/backlog/auto-findings-triage.md` (regenerated each tick).")

content = "\n".join(lines) + "\n"
with open(tmp_file, "w") as f:
    f.write(content)

print(f"update-startup-context: {total_open} open, {total_closed} auto_closed across {len(files)} detector(s) → {os.path.relpath(out_file, root_dir)}")
PY

mv "$TMP_FILE" "$OUT_FILE"
