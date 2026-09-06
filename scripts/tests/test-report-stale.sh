#!/usr/bin/env bash
# test-report-stale.sh — report-stale flags cold notes, spares fresh ones, exits 0.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/vault/learnings" "$TMP/vault/sessions"

TODAY="$(date +%Y-%m-%d)"
OLD="$(date -v-400d +%Y-%m-%d 2>/dev/null || date -d '400 days ago' +%Y-%m-%d)"
MID="$(date -v-60d  +%Y-%m-%d 2>/dev/null || date -d '60 days ago'  +%Y-%m-%d)"

# fresh learning — NOT stale (threshold 365d)
printf -- '---\ndate: %s\ntype: learning\n---\n# fresh\n' "$TODAY" > "$TMP/vault/learnings/fresh.md"
# cold learning — stale (400d > 365d)
printf -- '---\ndate: %s\ntype: learning\n---\n# cold\n' "$OLD" > "$TMP/vault/learnings/cold.md"
# 60-day session — stale (threshold 30d)
printf -- '---\ndate: %s\ntype: session\n---\n# oldsession\n' "$MID" > "$TMP/vault/sessions/old.md"

out="$(cd "$ROOT_DIR" && AGENTBRAIN_TEST_ROOT="$TMP" bash scripts/reports/report-stale.sh --list)"
echo "$out" | grep -q "local/learnings/cold.md" || { echo "FAIL: cold learning not flagged"; exit 1; }
echo "$out" | grep -q "local/sessions/old.md"   || { echo "FAIL: old session not flagged"; exit 1; }
if echo "$out" | grep -q "local/learnings/fresh.md"; then echo "FAIL: fresh learning wrongly flagged"; exit 1; fi

# --json is valid JSON and exit 0
(cd "$ROOT_DIR" && AGENTBRAIN_TEST_ROOT="$TMP" bash scripts/reports/report-stale.sh --json) | jq . >/dev/null || { echo "FAIL: --json not valid"; exit 1; }
echo "PASS test-report-stale"
