#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-check-prerequisites.sh — unit tests for scripts/check-prerequisites.sh:
# the version_ge helper (sourced without running the checks) + a smoke run on
# this (equipped) machine.
# shellcheck disable=SC2015  # `cond && pass || fail` is the intended test-assert idiom here
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/check-prerequisites.sh"
PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

# Source just the helpers (AGENTBRAIN_PREREQ_LIB=1 returns before the checks run).
# shellcheck source=/dev/null
AGENTBRAIN_PREREQ_LIB=1 source "$SCRIPT"

version_ge 3.13.1 3.9     && pass "3.13.1 >= 3.9"          || fail "3.13.1 >= 3.9"
version_ge 3.9 3.9        && pass "3.9 >= 3.9 (equal)"     || fail "3.9 == 3.9"
version_ge 20.11.0 18.0.0 && pass "20.11.0 >= 18.0.0"      || fail "20.11.0 >= 18"
version_ge 17.9.9 18.0.0  && fail "17.9.9 should be < 18"  || pass "17.9.9 < 18.0.0"
version_ge 1.2.19 1.2.20  && fail "1.2.19 < 1.2.20"        || pass "1.2.19 < 1.2.20"

# Smoke run on this (equipped) machine: exits 0, prints the header + a git line.
out="$(bash "$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "exits 0 on equipped machine" || fail "exit=$rc on equipped machine"
printf '%s' "$out" | grep -q "Prerequisites" && pass "prints header" || fail "no header"
printf '%s' "$out" | grep -q "git" && pass "reports git" || fail "no git line"

echo "  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
