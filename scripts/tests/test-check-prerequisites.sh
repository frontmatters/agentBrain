#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-check-prerequisites.sh — unit tests for scripts/checks/check-prerequisites.sh:
# the version_ge helper (sourced without running the checks) + a smoke run on
# this (equipped) machine.
# shellcheck disable=SC2015  # `cond && pass || fail` is the intended test-assert idiom here
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/checks/check-prerequisites.sh"
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

# Platform first, prerequisites second. A remedy that names a command the
# machine does not have reads as authoritative and sends the reader nowhere:
# "brew install jq" on a Linux box was the actual report from a WSL install.
# These call pkg_hint for real rather than matching on its source text.
[ "$(PM=brew    pkg_hint jq)" = "brew install jq" ] \
	&& pass "macOS hint uses brew" || fail "macOS hint: $(PM=brew pkg_hint jq)"
[ "$(PM=apt-get pkg_hint jq)" = "sudo apt-get install -y jq" ] \
	&& pass "Debian hint uses apt-get" || fail "apt hint: $(PM=apt-get pkg_hint jq)"
[ "$(PM=dnf     pkg_hint jq)" = "sudo dnf install -y jq" ] \
	&& pass "Fedora hint uses dnf" || fail "dnf hint: $(PM=dnf pkg_hint jq)"
case "$(PM='' PLATFORM=linux pkg_hint jq)" in
	*brew*) fail "a Linux machine without a package manager is told to use brew" ;;
	*)      pass "no brew hint where brew cannot exist" ;;
esac

# WSL must be told apart from plain Linux: same kernel, different install story.
grep -q "microsoft|wsl" "$SCRIPT" && pass "WSL is detected separately" || fail "WSL folded into Linux"
grep -qE 'report (miss|old).*brew install' "$SCRIPT" \
	&& fail "an unconditional brew hint remains" || pass "no unconditional brew hint"

# The installer carries its own copy of this logic: install.sh is served
# standalone over HTTP and cannot source anything from the repo. The copy is
# deliberate, so the risk is that the two drift. These assertions are what keeps
# them together; the first report of "Homebrew as a prerequisite on WSL" came
# from the installer, not from this script, after this script had been fixed.
INST="$ROOT_DIR/scripts/installer/install.sh"
grep -q 'PLATFORM="other"' "$INST" \
	&& pass "installer detects the platform" || fail "installer has no platform detection"
grep -q "microsoft|wsl" "$INST" \
	&& pass "installer tells WSL from Linux" || fail "installer folds WSL into Linux"
grep -q 'pkg_hint()' "$INST" \
	&& pass "installer derives install hints" || fail "installer has no pkg_hint"
grep -qE '^\s*for pair in "Homebrew:brew"' "$INST" \
	&& fail "installer lists Homebrew unconditionally" || pass "installer lists Homebrew only on macOS"
grep -qE 'row "✗".*"(brew install|needs Xcode CLT)"' "$INST" \
	&& fail "installer still gives a macOS-only remedy unconditionally" \
	|| pass "installer remedies are platform-derived"

echo "  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
