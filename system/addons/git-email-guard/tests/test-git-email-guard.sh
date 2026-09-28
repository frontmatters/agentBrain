#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Tests for git-email-guard's pre-commit hook. Builds throwaway git repos in a
# tmpdir and runs the hook directly — no real commits, no network. Covers:
# whitelist match, whitelist miss (block), env-var fallback, skip-flag bypass,
# empty user.email, and the no-whitelist "allow with warning" path.
set -euo pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ADDON_DIR/hooks/pre-commit"

if ! command -v git >/dev/null 2>&1; then
	echo "SKIP: git not installed — git-email-guard needs it" >&2
	exit 0
fi

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

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

# Fresh repo with a configured author email. $1 = email, $2(optional) = whitelist content.
make_repo() {
	local dir="$1" email="$2"
	git -C "$dir" init -q
	git -C "$dir" config user.email "$email"
	git -C "$dir" config user.name "Test"
}

run_hook() { ( cd "$1"; shift; env "$@" bash "$HOOK" ); }

# --- whitelist match: allowed email passes (exit 0) ---
R1="$TEST_DIR/r1"; mkdir "$R1"; make_repo "$R1" "dev@example.com"
printf 'dev@example.com\nbiz@example.com  # inline comment ok\n' > "$R1/.gitemail-allowed"
rc=0; run_hook "$R1" >/dev/null 2>&1 || rc=$?
assert "whitelisted email passes" "$rc" "0"

# --- whitelist miss: non-listed email is blocked (exit 1) + loud message ---
R2="$TEST_DIR/r2"; mkdir "$R2"; make_repo "$R2" "personal@example.net"
printf 'dev@example.com\n' > "$R2/.gitemail-allowed"
rc=0; out="$(run_hook "$R2" 2>&1)" || rc=$?
assert "non-whitelisted email is blocked" "$rc" "1"
assert "block message is loud" "$(printf '%s' "$out" | grep -c 'BLOCKED')" "1"

# --- env-var fallback: no .gitemail-allowed, GIT_EMAIL_ALLOWED used ---
R3="$TEST_DIR/r3"; mkdir "$R3"; make_repo "$R3" "ci@example.com"
rc=0; run_hook "$R3" GIT_EMAIL_ALLOWED="a@x.com:ci@example.com" >/dev/null 2>&1 || rc=$?
assert "env-var whitelist allows match" "$rc" "0"
rc=0; run_hook "$R3" GIT_EMAIL_ALLOWED="a@x.com:b@y.com" >/dev/null 2>&1 || rc=$?
assert "env-var whitelist blocks miss" "$rc" "1"

# --- skip-flag bypass: GIT_EMAIL_GUARD=skip short-circuits everything ---
R4="$TEST_DIR/r4"; mkdir "$R4"; make_repo "$R4" "anything@nowhere.test"
printf 'dev@example.com\n' > "$R4/.gitemail-allowed"
rc=0; run_hook "$R4" GIT_EMAIL_GUARD=skip >/dev/null 2>&1 || rc=$?
assert "skip flag bypasses the guard" "$rc" "0"

# --- empty user.email: blocked with guidance (exit 1) ---
R5="$TEST_DIR/r5"; mkdir "$R5"; git -C "$R5" init -q; git -C "$R5" config user.name "Test"
# ensure no inherited global email leaks in
rc=0; out="$(run_hook "$R5" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null 2>&1)" || rc=$?
assert "empty user.email is blocked" "$rc" "1"
assert "empty-email message mentions user.email" "$(printf '%s' "$out" | grep -c 'user.email is empty')" "1"

# --- no whitelist + no env: allow with a warning (exit 0) ---
R6="$TEST_DIR/r6"; mkdir "$R6"; make_repo "$R6" "whoever@example.com"
rc=0; out="$(run_hook "$R6" 2>&1)" || rc=$?
assert "no whitelist allows the commit" "$rc" "0"
assert "no-whitelist path warns" "$(printf '%s' "$out" | grep -c 'allowing')" "1"

# ---- report ----
echo "passed=$passed failed=$failed"
if [ "$failed" -gt 0 ]; then
	printf '%s\n' "${failures[@]}" >&2
	exit 1
fi
