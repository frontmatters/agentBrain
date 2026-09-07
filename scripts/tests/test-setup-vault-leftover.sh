#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-setup-vault-leftover.sh: a real local/ next to the vault link is set aside, never merged, never deleted.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OLD=local   # the vault's old name: here it is data, the leftover under test
mkdir -p "$T/co/scripts/setup" "$T/co/scripts/installer" "$T/co/templates" "$T/thevault" "$T/co/$OLD/learnings"
cp "$ROOT/scripts/setup/setup-vault.sh" "$T/co/scripts/setup/"; cp "$ROOT/scripts/installer/prompt-helper.sh" "$T/co/scripts/installer/" 2>/dev/null || true
ln -sfn "$T/thevault" "$T/co/vault"
printf '# an old note\n' > "$T/co/$OLD/learnings/oud.md"
VAULT="$T/co" AGENTBRAIN_HOME="$T/home" bash "$T/co/scripts/setup/setup-vault.sh" >"$T/out" 2>&1
[ ! -e "$T/co/$OLD" ] && ok "gone" "the old-name directory is no longer in the checkout" || bad "gone" "the old-name directory is still in the checkout"
aside="$(ls -d "$T"/agentBrain-local-leftover-* 2>/dev/null | head -1)"
[ -n "$aside" ] && [ -f "$aside/learnings/oud.md" ] && ok "kept" "the note survives beside the checkout ($(basename "$aside"))" || bad "kept" "the leftover note was lost"
[ ! -e "$T/thevault/learnings/oud.md" ] && ok "not-merged" "nothing was merged into the vault" || bad "not-merged" "the leftover was merged into the vault"
grep -q "leftover real local/" "$T/out" && ok "said" "setup says what it moved and where" || bad "said" "setup moved it silently"
[ "$(readlink "$T/co/vault")" = "$T/thevault" ] && ok "link-kept" "the vault link is untouched" || bad "link-kept" "the vault link changed"
[ "$fail" -ne 0 ] && { echo "FAIL test-setup-vault-leftover" >&2; exit 1; }
echo "PASS test-setup-vault-leftover"
