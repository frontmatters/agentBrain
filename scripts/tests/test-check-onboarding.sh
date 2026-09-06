#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-check-onboarding.sh — unit tests for scripts/checks/check-onboarding.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
# The check answers "pending" instead of "incomplete" when the caller says an
# un-onboarded vault is expected (setup, the release gate's sandbox doctor).
# This test exercises the check itself, so it must not inherit that answer.
# Measured: red in every release check, green by hand, two cases each time.
unset AGENTBRAIN_ONBOARDING_PENDING_OK AGENTBRAIN_SETUP_PHASE
unset VAULT AGENTBRAIN_DIR AGENTBRAIN_VAULT_DIR AGENTBRAIN_LOCAL_DIR BRAIN_DIR BRAIN_ALIAS   # a fixture test owns its brain location
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-onboarding-XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts/checks" "$FIXTURE/vault/preferences/personal"
cp "$ROOT_DIR/scripts/checks/check-onboarding.sh" "$FIXTURE/scripts/checks/"
PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

PREFS="$FIXTURE/vault/preferences/personal"

# 1) A template placeholder → incomplete (exit != 0)
printf -- '---\n---\nThis is an example preference.\n' > "$PREFS/communication.md"
if (cd "$FIXTURE" && bash scripts/checks/check-onboarding.sh >/dev/null 2>&1); then
  fail "placeholder should report incomplete"; else pass "placeholder → incomplete"; fi

# 2) A README is ignored, not counted as a placeholder
printf -- 'This is an example README.\n' > "$PREFS/README.md"
printf -- '---\n---\nIk wil Nederlands, beknopt.\n' > "$PREFS/communication.md"
if (cd "$FIXTURE" && bash scripts/checks/check-onboarding.sh >/dev/null 2>&1); then
  pass "README ignored, personalized → complete"; else fail "README should be ignored"; fi

# 3) Missing personal dir → incomplete
rm -rf "$PREFS"
if (cd "$FIXTURE" && bash scripts/checks/check-onboarding.sh >/dev/null 2>&1); then
  fail "missing dir should be incomplete"; else pass "missing dir → incomplete"; fi

# 3b) setup phase: incomplete state reports pending and exits 0 (no red X mid-install)
mkdir -p "$PREFS"
printf -- '---\n---\nThis is an example preference.\n' > "$PREFS/communication.md"
if (cd "$FIXTURE" && AGENTBRAIN_SETUP_PHASE=1 bash scripts/checks/check-onboarding.sh 2>/dev/null | grep -q "pending"); then
  pass "setup phase → pending, exit 0"; else fail "setup phase should report pending"; fi

# 4) doctor wires the check into its vault-layer checks
if grep -q 'check-onboarding.sh' "$ROOT_DIR/scripts/checks/doctor.sh"; then
  pass "doctor runs check-onboarding"; else fail "doctor does not run check-onboarding"; fi

echo "  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
