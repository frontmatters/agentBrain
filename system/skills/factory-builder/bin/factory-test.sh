#!/usr/bin/env bash
set -euo pipefail
FACTORY="${FACTORY_PATH:-$PWD}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/factory-doctor.sh" --factory "$FACTORY"
# bash 3.2 (macOS default) has no mapfile/readarray: same result via read.
V=()
while IFS= read -r _fb_line; do V+=("$_fb_line"); done < <(python3 - "$FACTORY/factory.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); print(d.get('lanes',{}).get('next','')); print(d.get('commands',{}).get('test',''))
PY
)
NEXT="${V[0]}"; CMD="${V[1]:-}"
NEXT="${NEXT/#\~/$HOME}"
[ -n "$CMD" ] || { echo 'factory-test: no commands.test configured' >&2; exit 2; }
bash "$ROOT/factory-lane-origin.sh" "$FACTORY"
bash "$ROOT/factory-language-check.sh" --factory "$FACTORY" --lane next
cd "$NEXT"
bash --noprofile --norc -lc "$CMD"
echo "factory-test: PASS"
