#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd -P)"
FACTORY="${FACTORY_PATH:-$PWD}"
if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != --factory ] || [ ! -d "$2" ]; then
    echo 'usage: factory-leakscan.sh [--factory DIR]' >&2; exit 2
  fi
  FACTORY="$2"
fi
FACTORY="$(cd "$FACTORY" && pwd -P)"
profile="$(python3 "$HERE/factory-profile.py" "$FACTORY")" || exit 1
brain="$(cd "$HERE/../../../.." && pwd -P)"
scan="$brain/scripts/checks/check-token-argv.sh"
errors=0
for lane in dev next live; do
  path="$(python3 - "$profile" "$lane" <<'PY'
import json, sys
print(json.loads(sys.argv[1])['lanes'].get(sys.argv[2]) or '')
PY
)"
  if [ -z "$path" ] || [ ! -d "$path" ]; then
    echo "FAIL $lane lane missing: ${path:-unset}"
    errors=$((errors+1))
    continue
  fi
  if output="$(bash "$scan" --root "$path")"; then
    echo "$lane: $output"
  else
    rc=$?
    if [ "$rc" -eq 2 ]; then echo "FAIL $lane lane is not a git checkout: $path"; else
      while IFS= read -r line; do
        case "$line" in FAIL\ *) echo "FAIL $lane: $path/${line#FAIL }" ;; esac
      done <<< "$output"
    fi
    errors=$((errors+1))
  fi
done
if [ "$errors" -gt 0 ]; then echo "factory-leakscan: FAIL ($errors lane(s))"; exit 1; fi
echo 'factory-leakscan: PASS (3 lanes)'
