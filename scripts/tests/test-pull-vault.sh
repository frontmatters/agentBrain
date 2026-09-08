#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-pull-vault.sh — the session-start pull brings notes in, refuses to guess, stays quiet.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
BIN="$ROOT/scripts/sync/pull-vault.sh"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
gq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
git init --quiet --bare "$T/origin.git"
for c in a b; do
	git clone --quiet "$T/origin.git" "$T/$c" 2>/dev/null
	git -C "$T/$c" config user.email t@t.t; git -C "$T/$c" config user.name t; git -C "$T/$c" config commit.gpgsign false
done
echo "one" > "$T/a/note.md"; gq "$T/a" add .; gq "$T/a" commit -m one; gq "$T/a" push -u origin HEAD
gq "$T/b" pull; gq "$T/b" branch -u origin/main 2>/dev/null || gq "$T/b" branch -u origin/master
run() { PULL_VAULT_DIR="$1" GITEA_HELPER_PATH=/nonexistent bash "$BIN" "${@:2}" 2>&1; }

out="$(run "$T/b")"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "current" "already current: silent, exit 0" || bad "current" "rc=$rc out=[$out]"

echo "two" > "$T/a/second.md"; gq "$T/a" add .; gq "$T/a" commit -m two; gq "$T/a" push
out="$(run "$T/b")"; rc=$?
[ "$rc" -eq 0 ] && [ -f "$T/b/second.md" ] && [ "$out" = "vault: pulled 1 commit(s)" ] && ok "pull" "a note pushed elsewhere comes in ($out)" || bad "pull" "rc=$rc out=[$out] file=$([ -f "$T/b/second.md" ] && echo yes || echo no)"
case "$out" in *origin.git*|*"$T"*) bad "quiet" "output names the remote or a path: $out" ;; *) ok "quiet" "no remote URL or path in the output" ;; esac

echo "three" > "$T/a/third.md"; gq "$T/a" add .; gq "$T/a" commit -m three; gq "$T/a" push
echo "mine" > "$T/b/mine.md"; gq "$T/b" add .; gq "$T/b" commit -m mine
before="$(git -C "$T/b" rev-parse HEAD)"
out="$(run "$T/b")"; rc=$?
after="$(git -C "$T/b" rev-parse HEAD)"
[ "$rc" -eq 0 ] && [ "$before" = "$after" ] && printf '%s' "$out" | grep -q "diverged" && ok "diverged" "diverged: says so, changes nothing, exit 0 ($out)" || bad "diverged" "rc=$rc out=[$out]"
out="$(run "$T/b" --strict)"; rc=$?
[ "$rc" -ne 0 ] && ok "strict" "--strict exits non-zero on divergence" || bad "strict" "rc=$rc"

mv "$T/origin.git" "$T/gone.git"
out="$(PULL_VAULT_BUDGET=6 run "$T/b")"; rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "offline" "remote unreachable: silent, exit 0" || bad "offline" "rc=$rc out=[$out]"
mv "$T/gone.git" "$T/origin.git"

[ "$fail" -ne 0 ] && { echo "FAIL test-pull-vault" >&2; exit 1; }
echo "PASS test-pull-vault"
