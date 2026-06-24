#!/usr/bin/env bash
# check-rules-pointer-sync.sh — verify the shared agentbrain-pointer.sh block
# contains all expected clauses. Per-agent rules-files (CLAUDE.md, etc.) live
# OUTSIDE the vault (~/.claude/, ~/.copilot/), so we can't check those from
# doctor — but we can ensure the source-of-truth (pointer.sh) is complete,
# so future setup-<client>.sh installs will inherit a correct block.
#
# Each EXPECTED_CLAUSE below represents a feature that should appear in
# every agent's rules-file. When a new feature lands (e.g. startup-context,
# new-note.sh discipline), add a clause-substring here.
#
# Runs in doctor's public_checks.
#
# Usage: bash scripts/check-rules-pointer-sync.sh

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POINTER_SH="$ROOT_DIR/scripts/agentbrain-pointer.sh"

if [ ! -f "$POINTER_SH" ]; then
	echo "check-rules-pointer-sync: $POINTER_SH missing" >&2
	exit 1
fi

# Substrings that MUST appear in the rendered pointer-block.
# Each represents a brain capability that all agents must know about.
EXPECTED_CLAUSES=(
	"learnings/patterns.md"
	"learnings/troubleshooting.md"
	"system/rules.md"
	"system/agent-config/shared.md"
	"system/skills.md"
	"local/sessions/startup-context.md"   # added 2026-05-24 (Phase 3 surface)
	"new-note.sh"                          # added 2026-05-24 (discipline framework Layer 3)
	"Self-learning"                        # write-back protocol pointer
)

PASS=0
FAIL=0
# Render block to a string by calling the function with test args
RENDERED="$(bash -c "source '$POINTER_SH' && agentbrain_pointer_block /test/vault test.md")"

for clause in "${EXPECTED_CLAUSES[@]}"; do
	if echo "$RENDERED" | grep -qF "$clause"; then
		echo "  ✓ pointer-block contains: '$clause'"
		PASS=$((PASS+1))
	else
		echo "  ✗ pointer-block MISSING expected clause: '$clause'" >&2
		FAIL=$((FAIL+1))
	fi
done

if [ "$FAIL" -gt 0 ]; then
	echo "check-rules-pointer-sync: $FAIL clause(s) missing, $PASS present"
	exit 1
fi
echo "check-rules-pointer-sync: ✅ all $PASS expected clauses present"
