#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-setup-alias-guard.sh — setup only accepts an ~/agentBrain alias that is a checkout.
#
# On a machine where ~/agentBrain already existed as something else (an old
# install, a vault cloned there by mistake) setup left it alone, wrote every
# skill link and client pointer through it, and the doctor failed in 29 places
# (a second machine, 2026-09-07). The alias is created when absent, repaired when
# dangling, kept when it is another checkout, and refused otherwise.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

FN="$(sed -n '/^ensure_brain_alias() {/,/^}/p' "$ROOT/scripts/setup/setup.sh")"
[ -n "$FN" ] || { bad "present" "no ensure_brain_alias in setup.sh"; echo "FAIL test-setup-alias-guard" >&2; exit 1; }
grep -q '^ensure_brain_alias "\$BRAIN_ALIAS" "\$VAULT" || exit 1' "$ROOT/scripts/setup/setup.sh" \
	&& ok "wired" "setup stops when the alias is refused" || bad "wired" "the guard is defined but its result is ignored"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/co1/scripts" "$T/co2/scripts" "$T/plain-dir/system"; : > "$T/co1/scripts/brain.sh"; : > "$T/co2/scripts/brain.sh"
{ printf 'GREEN=; YELLOW=; NC=\nconfirm() { return 0; }\n'; printf '%s\n' "$FN"; } > "$T/fn.sh"
run() { bash -c ". '$T/fn.sh'; ensure_brain_alias '$1' '$2'" >"$T/out" 2>&1; }

run "$T/absent" "$T/co1"; rc=$?
[ "$rc" -eq 0 ] && [ "$(readlink "$T/absent")" = "$T/co1" ] && ok "absent" "created -> checkout" || bad "absent" "rc=$rc link=$(readlink "$T/absent" 2>/dev/null)"

ln -s "$T/gone" "$T/dangling"; run "$T/dangling" "$T/co1"; rc=$?
[ "$rc" -eq 0 ] && [ "$(readlink "$T/dangling")" = "$T/co1" ] && ok "dangling" "repaired after confirmation" || bad "dangling" "rc=$rc link=$(readlink "$T/dangling")"

ln -s "$T/co2" "$T/other"; run "$T/other" "$T/co1"; rc=$?
[ "$rc" -eq 0 ] && [ "$(readlink "$T/other")" = "$T/co2" ] && ok "other-checkout" "another checkout is kept (brain use decides)" || bad "other-checkout" "rc=$rc link=$(readlink "$T/other")"

run "$T/plain-dir" "$T/co1"; rc=$?
[ "$rc" -ne 0 ] && grep -q "not an agentBrain checkout" "$T/out" && ok "plain-dir" "a directory that is no checkout is refused with the fix" || bad "plain-dir" "rc=$rc: $(head -1 "$T/out")"
[ -d "$T/plain-dir/system" ] && ok "untouched" "the refused directory is left as it was" || bad "untouched" "the refused directory was altered"

[ "$fail" -ne 0 ] && { echo "FAIL test-setup-alias-guard" >&2; exit 1; }
echo "PASS test-setup-alias-guard"
