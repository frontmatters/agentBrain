#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-addons-release.sh — aggregate release gate for add-on tests and coverage.
# Functional tests cover shell add-ons; Bun coverage covers the TypeScript add-ons
# that ship executable source. Pointer/AI-driven add-ons are checked statically.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agentbrain-addon-gate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

cd "$ROOT"
echo "== ABH integration contract =="
bash scripts/test-abh-integration.sh

echo "== functional add-on suites =="
bash scripts/addons.sh test >"$TMP/addons.log" 2>&1
cat "$TMP/addons.log" | tail -8

echo "== TypeScript coverage =="
run_coverage() {
  local id="$1" dir="$2" min="$3" output="$TMP/$1.log" line lines
  (cd "$ROOT/$dir" && bun test --coverage) >"$output" 2>&1
  line="$(grep -E '^All files[[:space:]]*\|' "$output" | tail -1)"
  [ -n "$line" ] || { echo "coverage gate: $id produced no summary" >&2; return 1; }
  lines="$(printf '%s\n' "$line" | awk -F'|' '{gsub(/[[:space:]]/, "", $3); print $3}')"
  printf '%-22s lines %s%% (minimum %s%%)\n' "$id" "$lines" "$min"
  awk -v got="$lines" -v min="$min" 'BEGIN { exit !(got + 0 >= min + 0) }' || {
    echo "coverage gate: $id below minimum" >&2
    return 1
  }
}

# Thresholds are deliberately scoped to the current testable source surfaces.
# The aggregate gate must not pretend that orchestration/network code has the same
# unit-testability as pure parsers and registry logic.
run_coverage "agentbrain-mcp" "system/addons/agentbrain-mcp" 90
run_coverage "extract-learnings" "system/addons/extract-learnings" 90
run_coverage "youtube-digest" "system/addons/youtube-digest" 75

echo "== static add-on registry =="
bash scripts/checks/check-addons.sh

echo "Aggregate add-on release gate: PASS"
