#!/usr/bin/env bash
set -euo pipefail
FACTORY="${FACTORY_PATH:-$PWD}"
[ "${1:-}" = --confirm ] || { echo 'factory-rollback: destructive; rerun with --confirm' >&2; exit 2; }
# bash 3.2 (macOS default) has no mapfile/readarray: same result via read.
V=()
while IFS= read -r _fb_line; do V+=("$_fb_line"); done < <(python3 - "$FACTORY/factory.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); print(d['lanes']['live'])
PY
)
LIVE="${V[0]/#\~/$HOME}"
REF_FILE="$FACTORY/R&D/logs/factory-previous-live-ref"
[ -s "$REF_FILE" ] || { echo 'factory-rollback: no recorded previous live ref' >&2; exit 2; }
REF=$(tr -d '[:space:]' < "$REF_FILE")
git -C "$LIVE" reset --hard "$REF"
echo "factory-rollback: live reset to $(git -C "$LIVE" rev-parse --short HEAD)"
