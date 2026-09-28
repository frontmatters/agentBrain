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

# `git config --local` in a worktree reads the config of the whole worktree
# family, so another session's `push -u` lands in this snapshot. Outcome 2
# names it as shared instead of blaming whichever check happened to be running.
b="$(repo_snapshot)"; git config branch.main.merge refs/heads/main
rc=0; repo_snapshot_diff "$b" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && ok "shared" "a branch upstream is reported as shared, not as the check's doing" || bad "shared" "expected outcome 2 for a branch key, got $rc"
git config --unset branch.main.merge

# And the narrowness has to hold: a fixture must not be able to hide a real
# write behind a branch key. One user.email in the same delta puts it back at
# outcome 1, where the check is named and the run stops.
b="$(repo_snapshot)"; git config branch.main.merge refs/heads/main; git config user.email hide@example.invalid
rc=0; repo_snapshot_diff "$b" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "mixed" "a real write alongside a branch key still names the check" || bad "mixed" "expected outcome 1 for a mixed delta, got $rc"
git config --unset branch.main.merge; git config --unset user.email

# doctor must act on the difference, not merely receive it: outcome 2 leaves
# $touched empty, which is what keeps the run going.
grep -q 'snap_rc" -eq 2' "$ROOT/scripts/checks/doctor.sh" && ok "doctor-shared" "doctor distinguishes shared state from a check's own write" || bad "doctor-shared" "doctor treats every snapshot change as the check's doing"

grep -q 'repo_snapshot' "$ROOT/scripts/checks/doctor.sh" && ok "doctor-uses" "doctor snapshots around every check" || bad "doctor-uses" "doctor does not use the snapshot"
if [ "$fail" -eq 0 ]; then echo "PASS test-repo-snapshot"; else echo "FAIL test-repo-snapshot" >&2; exit 1; fi
