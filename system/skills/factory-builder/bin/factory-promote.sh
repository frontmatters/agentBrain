#!/usr/bin/env bash
set -euo pipefail
FACTORY="${FACTORY_PATH:-$PWD}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/factory-check.sh"
# bash 3.2 (macOS default) has no mapfile/readarray: same result via read.
V=()
while IFS= read -r _fb_line; do V+=("$_fb_line"); done < <(python3 - "$FACTORY/factory.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); print(d['lanes']['next']); print(d['lanes']['live'])
PY
)
NEXT="${V[0]/#\~/$HOME}"; LIVE="${V[1]/#\~/$HOME}"
NEXT_BRANCH=$(git -C "$NEXT" branch --show-current)
[ -n "$NEXT_BRANCH" ] || { echo 'factory-promote: next is detached' >&2; exit 2; }
[ "$(git -C "$NEXT" rev-parse --git-common-dir)" = "$(git -C "$LIVE" rev-parse --git-common-dir)" ] || { echo 'factory-promote: lanes do not share a git repository' >&2; exit 2; }
bash "$ROOT/factory-lane-origin.sh" "$FACTORY"
PREVIOUS=$(git -C "$LIVE" rev-parse HEAD)
mkdir -p "$FACTORY/R&D/logs"
printf '%s\n' "$PREVIOUS" > "$FACTORY/R&D/logs/factory-previous-live-ref"
git -C "$LIVE" merge --ff-only "$NEXT_BRANCH"
echo "factory-promote: live now at $(git -C "$LIVE" rev-parse --short HEAD)"
