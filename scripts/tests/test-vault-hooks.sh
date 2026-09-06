#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-vault-hooks.sh — the vault hook a fresh install gets is the one that gates.
#
# The versioned scripts/hooks/vault-pre-commit.sh carried one layer (note ids)
# while the maintainer's vault ran four, in a private .githooks/pre-commit the
# framework never saw. A new user's vault commits went through no secret scan,
# no NDA gate and no intake check, and every doctor run was green because doctor
# tested the maintainer's copy. This test installs the VERSIONED hook into a
# throwaway repo and makes it refuse something.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SRC="$ROOT/scripts/hooks/vault-pre-commit.sh"
fail=0
ok() { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

for layer in validate-note-id check-vault-private check-nda check-intake; do
	grep -q "$layer" "$SRC" && ok "has-$layer" "versioned hook runs $layer" || bad "has-$layer" "versioned hook lacks $layer"
done
grep -q 'core.hooksPath' "$ROOT/scripts/sync/sync-vault.sh" &&
	ok "hookspath-aware" "sync installs into the directory hooksPath names" ||
	bad "hookspath-aware" "sync still drops the hook into .git/hooks unconditionally"
[ -f "$ROOT/scripts/hooks/vault-post-commit.sh" ] && ok "post-commit" "post-commit is versioned too" || bad "post-commit" "post-commit hook is not in the framework"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP" && git init -q . && git config user.email t@t && git config user.name t
install -m 0755 "$SRC" .git/hooks/pre-commit
printf '# clean\n\nnothing hidden\n' > clean.md && git add clean.md
git -c commit.gpgsign=false commit -qm clean >/dev/null 2>&1 && ok "clean-passes" "a clean note commits" || bad "clean-passes" "the hook refused a clean note"
# Written as an escape: this file must itself pass the check it tests.
python3 -c "open('dirty.md','w').write('# note\n\nhidden\u200bword\n')" && git add dirty.md
if git -c commit.gpgsign=false commit -qm dirty >"$TMP/out" 2>&1; then
	bad "intake-gates" "a zero-width character was committed through the versioned hook"
else
	grep -qi "intake\|invisible" "$TMP/out" && ok "intake-gates" "the versioned hook refuses an invisible character" || bad "intake-gates" "refused, but not by the intake layer: $(head -2 "$TMP/out")"
fi

if [ "$fail" -eq 0 ]; then echo "PASS test-vault-hooks"; else echo "FAIL test-vault-hooks" >&2; exit 1; fi
