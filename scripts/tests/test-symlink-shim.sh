#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-symlink-shim.sh — a commit staged through a symlink must not lie.
#
# `git add scripts/doctor.sh` where doctor.sh is a link into scripts/checks/
# stages the unchanged link and nothing else; the commit succeeds, the hooks
# pass, doctor stays green, and the message describes work the tree does not
# hold. Three commits shipped that way in one afternoon.
#
# The first guard refused on the STATE (dirty, unstaged shim target) and so
# refused every deliberate partial commit too. State cannot tell the two
# apart; the commit message can. So: pre-commit warns and names the real path,
# commit-msg refuses only when the message claims the file.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
PRE="$ROOT/.githooks/pre-commit"; MSGHOOK="$ROOT/.githooks/commit-msg"; CHECK="$ROOT/scripts/checks/check-shim-staging.sh"
fail=0
ok() { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p scripts/checks
cp "$CHECK" scripts/checks/   # the hooks look for it relative to the repo root
printf '#!/usr/bin/env bash\necho one\n' > scripts/checks/real.sh
ln -s checks/real.sh scripts/real.sh
git add -A && git commit -qm seed
msg() { printf '%s\n' "$1" > "$TMP/msg"; printf '%s' "$TMP/msg"; }
pre() { bash "$PRE" >/dev/null 2>"$TMP/err"; }
cm() { bash "$MSGHOOK" "$1" >/dev/null 2>"$TMP/err"; }

# The mistake: edit through the link, stage the link, describe the work.
printf 'echo two\n' >> scripts/real.sh
git add scripts/real.sh
pre && ok "pre-warns-passes" "pre-commit lets it through" || bad "pre-warns-passes" "pre-commit refused a state it cannot judge"
grep -q 'scripts/checks/real.sh' "$TMP/err" && ok "pre-names-target" "and names the real path" || bad "pre-names-target" "warning does not name the real path"
cm "$(msg 'fix(real): make real.sh say two')" && bad "claim-refused" "a message claiming real.sh went through with real.sh absent" || ok "claim-refused" "a message that claims the file is refused"
grep -q 'scripts/checks/real.sh' "$TMP/err" && ok "claim-names-target" "the refusal names the real path" || bad "claim-names-target" "refusal does not say where the change is"
cm "$(msg 'fix(scripts/real.sh): say two')" && bad "claim-by-link" "naming the LINK path was not caught" || ok "claim-by-link" "naming the link path is caught too"

# Honest partial commit: the message does not claim the dirty file.
printf 'x\n' > other.txt; git add other.txt
cm "$(msg 'chore: add other.txt')" && ok "partial-passes" "a partial commit that claims nothing about it passes" || bad "partial-passes" "an honest partial commit was refused"

# The fix: stage the real path. No warning, no refusal.
git add scripts/checks/real.sh
pre && ! grep -q 'symlink' "$TMP/err" && ok "target-staged" "staging the target: silent pass" || bad "target-staged" "staging the target still warned or refused"
cm "$(msg 'fix(real): make real.sh say two')" && ok "claim-with-target" "the claim is true now, so it passes" || bad "claim-with-target" "refused even though the file is in the commit"

# Partial staging of the target is deliberate and passes.
git reset -q; printf 'echo three\n' >> scripts/checks/real.sh; git add scripts/checks/real.sh; printf 'echo four\n' >> scripts/checks/real.sh
cm "$(msg 'fix(real): three')" && ok "partial-target" "a partially staged target passes" || bad "partial-target" "partial staging was refused"

if [ "$fail" -eq 0 ]; then echo "PASS test-symlink-shim"; else echo "FAIL test-symlink-shim" >&2; exit 1; fi
