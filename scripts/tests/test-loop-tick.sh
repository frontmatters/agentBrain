#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-loop-tick.sh — smoke test for the self-improving-loop tick chain:
# capture-findings.sh + update-startup-context.sh. Builds a fixture vault,
# runs loop-tick, asserts:
#   - exit 0
#   - local/findings/check-vault-content.json written with valid JSON
#   - local/sessions/startup-context.md written and non-empty
#   - local/metrics/findings-history.jsonl appended with valid JSONL row
#
# Smoke-level only — full correctness lives in the individual scripts'
# logic. This catches "loop-tick breaks the chain" regressions.
#
# Runs in doctor's local_checks (depends on local/ but doesn't write to it).

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-loop-tick-XXXXXX")"
# A fixture brain has the layout setup makes: vault/ is the directory, local/ the alias.
mkdir -p "$FIXTURE/vault" && ln -sfn vault "$FIXTURE/local"
trap 'rm -rf "$FIXTURE"' EXIT

# Minimal vault: brain.json + scripts (copies, not symlinks) + an empty local/
# check-vault-content.sh must live at scripts/checks/ (its ROOT_DIR climbs two
# levels, production layout) with the scripts/-root symlink capture expects.
mkdir -p "$FIXTURE/scripts/checks" "$FIXTURE/scripts/flow" "$FIXTURE/scripts/reports" "$FIXTURE/vault/learnings"
cp "$ROOT_DIR/brain.json" "$FIXTURE/"
cp "$ROOT_DIR/scripts/uuid5-gen.sh" \
   "$ROOT_DIR/scripts/capture-findings.sh" \
   "$FIXTURE/scripts/"
mkdir -p "$FIXTURE/scripts/lib"
# check-vault-content reads the shared note-schema exemptions from here
# (same file the wash-vault fixer reads); it fails loudly without them.
cp "$ROOT_DIR/scripts/lib/exempt-schema-paths.txt" "$FIXTURE/scripts/lib/"
cp "$ROOT_DIR/scripts/checks/check-vault-content.sh" "$FIXTURE/scripts/checks/"
ln -s checks/check-vault-content.sh "$FIXTURE/scripts/check-vault-content.sh"
cp "$ROOT_DIR/scripts/flow/update-startup-context.sh" \
   "$ROOT_DIR/scripts/flow/loop-tick.sh" \
   "$FIXTURE/scripts/flow/"
cp "$ROOT_DIR/scripts/reports/render-findings-backlog.sh" "$FIXTURE/scripts/reports/"

# Add one valid note so check-vault-content has something to process
NS="$(python3 -c 'import json; print(json.load(open("'"$FIXTURE"'/brain.json"))["namespace"])')"
UUID="$(python3 -c "import uuid; print(uuid.uuid5(uuid.UUID('$NS'), 'agentBrain/local/learnings/seed'))")"
cat > "$FIXTURE/vault/learnings/seed.md" <<EOF
---
date: 2026-05-24
type: learning
tags: [seed]
id: $UUID
---
# Seed
EOF

# Run loop-tick against fixture (|| RC=$? guard: report via the asserts,
# not a silent set -e death)
RC=0
( cd "$FIXTURE" && bash scripts/flow/loop-tick.sh ) > "$FIXTURE/loop-tick.out" 2>&1 || RC=$?

PASS=0
FAIL=0
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }

if [ "$RC" = "0" ]; then pass "loop-tick exits 0"; else fail "loop-tick exit=$RC"; fi

if [ -f "$FIXTURE/vault/findings/check-vault-content.json" ]; then
	pass "findings JSON written"
else
	fail "findings JSON missing"
fi

if python3 -c "import json; json.load(open('$FIXTURE/vault/findings/check-vault-content.json'))" 2>/dev/null; then
	pass "findings JSON parses"
else
	fail "findings JSON malformed"
fi

if [ -s "$FIXTURE/vault/sessions/startup-context.md" ]; then
	pass "startup-context.md written + non-empty"
else
	fail "startup-context.md missing or empty"
fi

if [ -f "$FIXTURE/vault/metrics/findings-history.jsonl" ]; then
	pass "metrics jsonl written"
else
	fail "metrics jsonl missing"
fi

if [ -f "$FIXTURE/vault/metrics/findings-history.jsonl" ]; then
	if python3 -c "import json; [json.loads(l) for l in open('$FIXTURE/vault/metrics/findings-history.jsonl')]" 2>/dev/null; then
		pass "metrics jsonl rows parse"
	else
		fail "metrics jsonl rows malformed"
	fi
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
	echo "test-loop-tick: $FAIL failed, $PASS passed"
	echo "loop-tick output:" >&2
	cat "$FIXTURE/loop-tick.out" >&2
	exit 1
fi
echo "test-loop-tick: ✅ $PASS smoke assertions passed"
