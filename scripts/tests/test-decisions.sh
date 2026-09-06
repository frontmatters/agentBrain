#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Behavioural tests for scripts/checks/check-decisions.sh — runs entirely against tmpdir
# fixtures (AGENTBRAIN_DIR override), no install needed. Covers the ADR-discipline
# rules distilled from DeepSeek Harness's decision-record gate:
#   - a well-formed accepted ADR passes
#   - an invalid Status enum fails (exit 1)
#   - missing required bullets (Decision/Consequences) fails
#   - an accepted ADR without Alternatives WARNS (does not fail — warn-first rollout)
#   - a *proposed* ADR without Alternatives is silent (only accepted requires it)
#   - proposal-language in an accepted ADR warns
#   - no decision-records → clean no-op
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
CHECK="$ROOT_DIR/scripts/checks/check-decisions.sh"

passed=0
failed=0
failures=()
assert() {
	local desc="$1" actual="$2" expected="$3"
	if [ "$actual" = "$expected" ]; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		failures+=("$desc: expected '$expected', got '$actual'")
	fi
}

# run_check <decisions.md content> — writes it into a fresh tmp vault and runs the
# check. Sets RC (exit code) and OUT (merged stdout+stderr).
RC=0
OUT=""
run_check() {
	local content="$1" tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/vault/projects/p"
	printf '%s\n' "$content" >"$tmp/vault/projects/p/decisions.md"
	RC=0
	OUT="$(AGENTBRAIN_DIR="$tmp" bash "$CHECK" 2>&1)" || RC=$?
	rm -rf "$tmp"
}

# --- a well-formed accepted ADR passes cleanly ---
run_check '## ADR-001: Use X (2026-01-01)
- **Status**: accepted
- **Context**: needed a thing
- **Decision**: chose X
- **Alternatives**: Y — rejected, slower
- **Consequences**: fine'
assert "valid accepted ADR exits 0" "$RC" "0"
assert "valid accepted ADR reports OK" "$(printf '%s' "$OUT" | grep -c 'check-decisions: OK')" "1"

# --- invalid Status enum fails ---
run_check '## ADR-001: Use X (2026-01-01)
- **Status**: yolo
- **Decision**: chose X
- **Consequences**: fine'
assert "invalid Status exits 1" "$RC" "1"
assert "invalid Status names the ADR" "$(printf '%s' "$OUT" | grep -c 'ADR-001')" "1"
assert "invalid Status mentions Status" "$(printf '%s' "$OUT" | grep -ci 'status')" "1"

# --- missing required bullets fails ---
run_check '## ADR-001: Use X (2026-01-01)
- **Status**: accepted
- **Alternatives**: Y — rejected'
assert "missing Decision+Consequences exits 1" "$RC" "1"
assert "missing bullet flags Decision" "$(printf '%s' "$OUT" | grep -c 'missing Decision')" "1"

# --- accepted ADR without Alternatives WARNS, does not fail (warn-first rollout) ---
run_check '## ADR-002: JWT (2026-01-02)
- **Status**: accepted
- **Context**: stateless auth
- **Decision**: use JWT
- **Consequences**: token rotation needed'
assert "accepted w/o Alternatives exits 0 (warn only)" "$RC" "0"
assert "accepted w/o Alternatives warns" "$(printf '%s' "$OUT" | grep -c 'WARN')" "1"
assert "warning names Alternatives" "$(printf '%s' "$OUT" | grep -ci 'alternatives')" "1"

# --- a proposed ADR without Alternatives is silent (only accepted requires it) ---
run_check '## ADR-001: Explore X (2026-01-01)
- **Status**: proposed
- **Context**: c
- **Decision**: maybe X
- **Consequences**: to see'
assert "proposed w/o Alternatives exits 0" "$RC" "0"
assert "proposed w/o Alternatives does not warn" "$(printf '%s' "$OUT" | grep -c 'WARN')" "0"

# --- proposal-language in an accepted ADR warns ---
run_check '## ADR-001: Use X (2026-01-01)
- **Status**: accepted
- **Decision**: TBD, we should decide later
- **Alternatives**: Y — rejected
- **Consequences**: fine'
assert "proposal-language in accepted warns" "$(printf '%s' "$OUT" | grep -c 'WARN')" "1"

# --- Alternatives with sub-bullets (empty inline header) counts as present ---
run_check '## ADR-001: X (2026-01-01)
- **Status**: accepted
- **Decision**: chose X
- **Alternatives**:
  - Y — rejected, slower
  - Z — rejected, no team experience
- **Consequences**: fine'
assert "multi-line Alternatives exits 0" "$RC" "0"
assert "multi-line Alternatives does not warn" "$(printf '%s' "$OUT" | grep -c 'WARN')" "0"

# --- Status enum tolerates a trailing qualifier ("accepted (supersedes X)") ---
run_check '## ADR-002: Convert tokens (2026-08-17)
- **Status**: accepted (supersedes the probe approach)
- **Decision**: convert oklch to rgb
- **Alternatives**: keep oklch — Cytoscape cannot parse it
- **Consequences**: tokens resolved at build'
assert "accepted + trailing qualifier exits 0" "$RC" "0"
assert "accepted + trailing qualifier: no invalid-status" "$(printf '%s' "$OUT" | grep -c 'invalid Status')" "0"

# --- no decision-records → clean no-op ---
EMPTY_TMP="$(mktemp -d)"
RC=0
OUT="$(AGENTBRAIN_DIR="$EMPTY_TMP" bash "$CHECK" 2>&1)" || RC=$?
rm -rf "$EMPTY_TMP"
assert "empty vault exits 0" "$RC" "0"
assert "empty vault reports no records" "$(printf '%s' "$OUT" | grep -c 'no decision-records')" "1"

# --- summary ---
echo "test-decisions: $passed passed, $failed failed"
if [ "$failed" -gt 0 ]; then
	printf '  FAIL: %s\n' "${failures[@]}" >&2
	exit 1
fi
