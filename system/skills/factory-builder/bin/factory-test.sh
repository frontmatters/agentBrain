#!/usr/bin/env bash
set -euo pipefail
FACTORY="${FACTORY_PATH:-$PWD}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/factory-doctor.sh" --factory "$FACTORY"
# bash 3.2 (macOS default) has no mapfile/readarray: same result via read.
V=()
# Lanes and the test command come from the shared profile normalizer, so a
# composite factory is tested the same way as a standard one.
while IFS= read -r _fb_line; do V+=("$_fb_line"); done < <(python3 "$ROOT/factory-profile.py" "$FACTORY" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["lanes"]["next"] or ""); print(d["test"] or "")')
NEXT="${V[0]:-}"; CMD="${V[1]:-}"
[ -n "$NEXT" ] || { echo 'factory-test: no next lane configured' >&2; exit 2; }
[ -n "$CMD" ] || { echo 'factory-test: no commands.test configured' >&2; exit 2; }
bash "$ROOT/factory-lane-origin.sh" "$FACTORY"
bash "$ROOT/factory-language-check.sh" --factory "$FACTORY" --lane next
cd "$NEXT"
bash --noprofile --norc -lc "$CMD"
echo "factory-test: PASS"
