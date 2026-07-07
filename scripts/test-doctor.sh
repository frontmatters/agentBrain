#!/usr/bin/env bash
# test-doctor.sh — meta-test proving the doctor machinery itself works:
#   1) a clean repo -> doctor passes (exit 0)
#   2) an injected broken check -> doctor FAILS (exit != 0)   ← the part that matters
#   3) after removing the injection -> doctor passes again
# Standalone (NOT wired into doctor.sh — that would recurse). Run manually or in CI.
# Uses a canary markdown file with no frontmatter (check-frontmatter rejects it).
# Cleanup uses mv, never rm.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CANARY="system/doctor-selftest-canary.md"
STASH="/tmp/doctor-selftest-canary-$$.md"
cleanup() { if [ -f "$CANARY" ]; then mv -f "$CANARY" "$STASH" 2>/dev/null || true; fi; }
trap cleanup EXIT

passed=0
failed=0
chk() {
	if [ "$2" = "$3" ]; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		echo "FAIL $1: expected '$3', got '$2'" >&2
	fi
}

run_doctor() { bash scripts/doctor.sh --ci >/dev/null 2>&1 && echo 0 || echo 1; }

# 1) Clean baseline
chk "clean repo -> doctor passes" "$(run_doctor)" "0"

# 2) Inject a malformed public note -> check-frontmatter fails -> doctor must fail
printf '# canary\n\nno frontmatter here\n' > "$CANARY"
chk "broken check -> doctor FAILS" "$(run_doctor)" "1"

# 3) Remove the injection (mv, not rm) -> doctor passes again
mv -f "$CANARY" "$STASH"
chk "after fix -> doctor passes" "$(run_doctor)" "0"

echo "passed=$passed failed=$failed"
[ "$failed" -eq 0 ] || exit 1
