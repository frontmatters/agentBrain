#!/usr/bin/env bash
# test-list-space.sh — verify the --space opt-in view for list-learnings and
# list-projects: a space's own notes list on demand, the default view never
# surfaces them, and the slug guard rejects path-escape attempts.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLUG="__lstest__"
SP_LEARN="$ROOT_DIR/local/spaces/$SLUG/learnings"
SP_PROJ="$ROOT_DIR/local/spaces/$SLUG/projects/spaceprobeproj"
trap 'rm -rf "$ROOT_DIR/local/spaces/$SLUG"' EXIT
mkdir -p "$SP_LEARN" "$SP_PROJ"

LBIN="$ROOT_DIR/system/skills/list-learnings/bin/list-learnings"
PBIN="$ROOT_DIR/system/skills/list-projects/bin/list-projects"

# Probe learning — unique title so the assertion is real, not trivially-true.
NID="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "local/spaces/$SLUG/learnings/spaceprobe")"
printf -- '---\ntype: learning\ntags: [learning]\nid: %s\ndate: 2026-06-26\n---\n# SPACEPROBELEARN\n' "$NID" > "$SP_LEARN/spaceprobe.md"

# Probe project — unique status one-liner so the assertion is real.
PID="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "local/spaces/$SLUG/projects/spaceprobeproj/index")"
printf -- '---\ntype: project\ntags: [project]\nstatus: active\nid: %s\ndate: 2026-06-26\n---\n# spaceprobeproj\n\n## Status\nSPACEPROBEPROJ one-liner here.\n' "$PID" > "$SP_PROJ/index.md"

# 1. --space view lists the space learning
out="$(bash "$LBIN" --space "$SLUG" 2>/dev/null)"
echo "$out" | grep -qi "SPACEPROBELEARN" || { echo "FAIL: learnings --space view did not list the space learning"; exit 1; }

# 2. default learnings view does NOT surface the space learning
out2="$(bash "$LBIN" 2>/dev/null)"
echo "$out2" | grep -qi "SPACEPROBELEARN" && { echo "FAIL: default learnings view leaked a space learning"; exit 1; }

# 3. --space view lists the space project
pout="$(bash "$PBIN" --space "$SLUG" 2>/dev/null)"
echo "$pout" | grep -qi "spaceprobeproj" || { echo "FAIL: projects --space view did not list the space project"; exit 1; }

# 4. default projects view does NOT surface the space project
pout2="$(bash "$PBIN" 2>/dev/null)"
echo "$pout2" | grep -qi "spaceprobeproj" && { echo "FAIL: default projects view leaked a space project"; exit 1; }

# 5. slug guard — path-escape attempts must be rejected by both bins
bash "$LBIN" --space "../x" >/dev/null 2>&1 && { echo "FAIL: learnings accepted unsafe slug"; exit 1; }
bash "$PBIN" --space "../x" >/dev/null 2>&1 && { echo "FAIL: projects accepted unsafe slug"; exit 1; }
bash "$LBIN" --space "" >/dev/null 2>&1 && { echo "FAIL: learnings accepted empty slug"; exit 1; }
bash "$PBIN" --space "" >/dev/null 2>&1 && { echo "FAIL: projects accepted empty slug"; exit 1; }

echo "PASS test-list-space"
