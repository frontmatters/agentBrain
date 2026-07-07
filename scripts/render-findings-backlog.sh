#!/usr/bin/env bash
# render-findings-backlog.sh — the ACT bridge of the self-improving loop:
# turn open findings (local/findings/*.json, written by capture-findings.sh)
# into ONE standing, regenerated backlog note that any agent can pick up and
# execute. Closes the gap between "loop-tick counts findings" and "someone
# actually fixes them".
#
# Output: local/backlog/auto-findings-triage.md — AUTO-GENERATED, regenerated
# on every loop-tick; never edit it, fix the findings (next tick auto-closes
# them and they disappear from this note).
#
# Exit codes: 0 — wrote (or removed when zero open findings); 1 — failure.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FINDINGS_DIR="$ROOT_DIR/local/findings"
OUT_REL="local/backlog/auto-findings-triage"
OUT_FILE="$ROOT_DIR/$OUT_REL.md"
TMP_FILE="${OUT_FILE}.tmp.$$"

# Deterministic id: same path -> same UUID5, so regeneration never churns the id.
NOTE_ID="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "$OUT_REL")"

mkdir -p "$(dirname "$OUT_FILE")"

NOTE_ID="$NOTE_ID" python3 - "$FINDINGS_DIR" "$TMP_FILE" <<'PY'
import json, os, glob, sys
from datetime import datetime, timezone

findings_dir, tmp_file = sys.argv[1:3]
note_id = os.environ["NOTE_ID"]
today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

CAP_PER_SEVERITY = 25
SEV_ORDER = ["error", "warning", "info"]

open_findings = []
for path in sorted(glob.glob(os.path.join(findings_dir, "*.json"))):
    try:
        data = json.load(open(path))
    except (json.JSONDecodeError, OSError):
        continue
    for f in data.get("findings", []):
        if f.get("status", "open") == "open":
            f["_detector"] = data.get("detector", os.path.basename(path))
            open_findings.append(f)

lines = [
    "---",
    f"date: {today}",
    "type: backlog",
    "tags: [backlog, auto-generated, findings-triage]",
    "source: loop-tick",
    f"id: {note_id}",
    "---",
    "",
    "# Findings-triage (auto-gegenereerd)",
    "",
    "> AUTO-GENERATED door `scripts/render-findings-backlog.sh` (loop-tick).",
    "> NIET handmatig bewerken: los de finding op (of verwijder de bron),",
    "> dan auto-sluit de volgende loop-tick hem en verdwijnt hij hier.",
    "",
    f"Open findings: **{len(open_findings)}** (peildatum {today}).",
    "",
]

by_sev = {}
for f in open_findings:
    by_sev.setdefault(f.get("severity", "info"), []).append(f)

for sev in SEV_ORDER + sorted(set(by_sev) - set(SEV_ORDER)):
    items = by_sev.get(sev, [])
    if not items:
        continue
    lines.append(f"## {sev} ({len(items)})")
    lines.append("")
    for f in items[:CAP_PER_SEVERITY]:
        loc = f.get("file", "")
        msg = f.get("message", f.get("id", "?"))
        action = f.get("suggested_action", "")
        entry = f"- [ ] `{loc}` — {msg}" if loc else f"- [ ] {msg}"
        if action:
            entry += f"\n      → {action}"
        lines.append(entry)
    if len(items) > CAP_PER_SEVERITY:
        lines.append(f"- … nog {len(items) - CAP_PER_SEVERITY} {sev}-findings: zie `local/findings/*.json`")
    lines.append("")

lines.append("## Werkinstructie")
lines.append("")
lines.append("Pak findings van boven naar beneden (error eerst). Na het fixen:")
lines.append("`bash scripts/loop-tick.sh` draaien (of de nachtelijke tick afwachten)")
lines.append("— opgeloste findings sluiten automatisch en deze lijst krimpt.")
lines.append("")

with open(tmp_file, "w") as fh:
    fh.write("\n".join(lines) + "\n")
print(f"render-findings-backlog: {len(open_findings)} open finding(s) -> {os.path.basename(tmp_file).rsplit('.tmp', 1)[0]}")
PY

mv "$TMP_FILE" "$OUT_FILE"
