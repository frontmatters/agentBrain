#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-git-env.sh — a fixture built under a hook's GIT_DIR lands in the fixture.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0
ok() { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; [ -n "$TMP" ] || exit 1
# A stand-in for the real checkout, and the GIT_DIR a worktree hook would export.
git -C "$TMP" init -q real && git -C "$TMP/real" -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
export GIT_DIR="$TMP/real/.git"
# What a test does, without the fix: the fixture command hits the "real" repo.
mkdir -p "$TMP/fixture"; git -C "$TMP/fixture" init -q . 2>/dev/null; git -C "$TMP/fixture" config user.email test@example.invalid
[ "$(git -C "$TMP/real" config --local user.email)" = "test@example.invalid" ] && ok "reproduces" "with GIT_DIR set, git -C fixture wrote to the real repo" || bad "reproduces" "could not reproduce the leak; the test proves nothing"
git -C "$TMP/real" config --unset user.email
# With the fix.
. "$ROOT/scripts/lib/git-env.sh"; clear_git_env
[ -z "${GIT_DIR:-}" ] && ok "cleared" "GIT_DIR is gone" || bad "cleared" "GIT_DIR survived"
rm -rf "$TMP/fixture"; mkdir -p "$TMP/fixture"; git -C "$TMP/fixture" init -q .; git -C "$TMP/fixture" config user.email test@example.invalid
[ -z "$(git -C "$TMP/real" config --local user.email)" ] && ok "contained" "the fixture's config write stays in the fixture" || bad "contained" "still wrote to the real repo"
[ -d "$TMP/fixture/.git" ] && ok "fixture-repo" "the fixture got its own repository" || bad "fixture-repo" "no repository in the fixture"
grep -q 'clear_git_env' "$ROOT/scripts/checks/doctor.sh" && ok "doctor" "doctor clears the hook's git environment before any check" || bad "doctor" "doctor does not clear it"
if [ "$fail" -eq 0 ]; then echo "PASS test-git-env"; else echo "FAIL test-git-env" >&2; exit 1; fi
