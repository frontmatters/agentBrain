#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-repo-snapshot.sh — a check that touches the checkout is named, whatever it touched.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0
ok() { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[ -n "$TMP" ] && cd "$TMP" || exit 1
git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m seed
. "$ROOT/scripts/lib/repo-snapshot.sh"

b="$(repo_snapshot)"; repo_snapshot_diff "$b" 2>/dev/null && ok "quiet" "nothing changed, nothing said" || bad "quiet" "reported a change where there was none"

b="$(repo_snapshot)"; git config user.email test@example.invalid
out="$(repo_snapshot_diff "$b" 2>&1)" && bad "config" "a config write went unnoticed" || { grep -q 'user.email=test@example.invalid' <<<"$out" && ok "config" "a config write is named" || bad "config" "reported, but not what changed"; }
git config --unset user.email

b="$(repo_snapshot)"; printf 'x\n' > clean.md; git add clean.md
repo_snapshot_diff "$b" 2>/dev/null && bad "index" "a staged file went unnoticed" || ok "index" "a staged file is named"
git reset -q

b="$(repo_snapshot)"; git -c user.email=t@t -c user.name=t commit -q --allow-empty -m stray
repo_snapshot_diff "$b" 2>/dev/null && bad "head" "a commit went unnoticed" || ok "head" "a commit is named"

# core.bare=true is the one that broke `git status` for the whole checkout.
b="$(repo_snapshot)"; git config core.bare true
repo_snapshot_diff "$b" 2>/dev/null && bad "bare" "core.bare went unnoticed" || ok "bare" "core.bare=true is named"
git config core.bare false

grep -q 'repo_snapshot' "$ROOT/scripts/checks/doctor.sh" && ok "doctor-uses" "doctor snapshots around every check" || bad "doctor-uses" "doctor does not use the snapshot"
if [ "$fail" -eq 0 ]; then echo "PASS test-repo-snapshot"; else echo "FAIL test-repo-snapshot" >&2; exit 1; fi
