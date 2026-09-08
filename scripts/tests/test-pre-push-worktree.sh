#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-pre-push-worktree.sh — the pre-push doctor validates the pushed commit,
# in its own worktree, however the working tree moves meanwhile.
#
# Twice in two days (2026-09-06, 07) a commit landed while the pre-push doctor
# ran over the working tree; the doctor saw HEAD change, blamed the running
# check and refused the push. The hook now checks out the pushed sha detached
# and runs the doctor there.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; mkdir -p "$R/scripts" "$R/.githooks"
git -C "$R" init -q; git -C "$R" config user.email t@t.t; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
cp "$ROOT/.githooks/pre-push" "$R/.githooks/pre-push"; chmod +x "$R/.githooks/pre-push"
# A doctor that records where and on what it ran, and fails on demand.
cat > "$R/scripts/doctor.sh" <<'D'
#!/usr/bin/env bash
printf 'cwd=%s\nhead=%s\nvault=%s\n' "$(pwd -P)" "$(git rev-parse HEAD)" "$( [ -L vault ] && readlink vault || echo none)" > "$DOCTOR_TRACE"
[ -f FAIL_ME ] && exit 1; exit 0
D
chmod +x "$R/scripts/doctor.sh"
mkdir -p "$T/vault"; ln -s "$T/vault" "$R/vault"; echo '{"namespace":"x"}' > "$R/brain.json"
printf 'vault\nbrain.json\n' > "$R/.gitignore"
echo one > "$R/a.txt"; git -C "$R" add -A; git -C "$R" commit -qm one; sha1="$(git -C "$R" rev-parse HEAD)"
echo two > "$R/a.txt"; git -C "$R" add -A; git -C "$R" commit -qm two; sha2="$(git -C "$R" rev-parse HEAD)"

# Push sha1 while HEAD is already sha2 and the working tree is dirty on top.
echo dirty >> "$R/a.txt"
export DOCTOR_TRACE="$T/trace"
out="$(cd "$R" && printf 'refs/heads/main %s refs/heads/main %s\n' "$sha1" "0000000000000000000000000000000000000000" | bash .githooks/pre-push origin x 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "passes" "hook exit 0 with a green doctor" || bad "passes" "rc=$rc: $out"
grep -q "^head=$sha1$" "$T/trace" && ok "pushed-sha" "the doctor ran on the pushed commit, not HEAD" || bad "pushed-sha" "$(cat "$T/trace")"
grep -q "^cwd=$(cd -P "$R" && pwd -P)$" "$T/trace" && bad "worktree" "the doctor ran in the checkout itself" || ok "worktree" "the doctor ran in a separate worktree"
grep -q "^vault=$T/vault$" "$T/trace" && ok "vault-link" "the vault link is in the worktree" || bad "vault-link" "$(grep vault= "$T/trace")"
[ "$(git -C "$R" worktree list | wc -l | tr -d ' ')" = "1" ] && ok "cleanup" "the worktree is removed afterwards" || bad "cleanup" "$(git -C "$R" worktree list)"
grep -q "dirty" "$R/a.txt" && ok "untouched" "the working tree is left as it was" || bad "untouched" "working tree changed"

# Run the way the post-commit auto-push runs it: with git's hook environment
# leaked in. The worktree must still be used.
: > "$T/trace"
out="$(cd "$R" && printf 'refs/heads/main %s refs/heads/main %s\n' "$sha1" "$sha2" | GIT_DIR=.git GIT_INDEX_FILE=.git/index GIT_PREFIX='' bash .githooks/pre-push origin x 2>&1)"; rc=$?
grep -q "^head=$sha1$" "$T/trace" && ! grep -q "^cwd=$(cd -P "$R" && pwd -P)$" "$T/trace" && ok "hook-env" "with GIT_DIR leaked in, the worktree is still used (rc=$rc)" || bad "hook-env" "rc=$rc $(cat "$T/trace") $out"

# A red doctor blocks the push.
touch "$R/FAIL_ME"; git -C "$R" add FAIL_ME; git -C "$R" commit -qm fail; sha3="$(git -C "$R" rev-parse HEAD)"
out="$(cd "$R" && printf 'refs/heads/main %s refs/heads/main %s\n' "$sha3" "$sha2" | bash .githooks/pre-push origin x 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "BLOCKED" && ok "blocks" "a red doctor blocks the push" || bad "blocks" "rc=$rc"

# A branch delete pushes the null sha: nothing to validate, exit 0.
: > "$T/trace"
out="$(cd "$R" && printf '(delete) 0000000000000000000000000000000000000000 refs/heads/old %s\n' "$sha1" | bash .githooks/pre-push origin x 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "delete" "a ref delete is not validated (exit $rc)" || bad "delete" "rc=$rc: $out"

[ "$fail" -ne 0 ] && { echo "FAIL test-pre-push-worktree" >&2; exit 1; }
echo "PASS test-pre-push-worktree"
