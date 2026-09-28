#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-vault-var-names.sh — one vault location, whichever name you set it with.
#
# The installer documents AGENTBRAIN_VAULT (and --vault=PATH). The runtime read
# AGENTBRAIN_VAULT_DIR, falling back to AGENTBRAIN_LOCAL_DIR. Nothing connected
# them, so setting the documented name moved where the vault was CREATED and not
# where any later script LOOKED: the install obeyed and everything after it did
# not. Three spellings for one idea, split across the two halves that must agree.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

pass=0; fail=0
t_ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
t_bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

resolved() { # resolved VAR=value...
	env -u AGENTBRAIN_VAULT -u AGENTBRAIN_VAULT_DIR -u AGENTBRAIN_LOCAL_DIR "$@" \
		bash -c '. "'"$ROOT_DIR"'/scripts/lib/vault.sh"; printf "%s" "$VAULT_DIR"'
}

# --- 1. each of the three names reaches the runtime --------------------------
for v in AGENTBRAIN_VAULT AGENTBRAIN_VAULT_DIR AGENTBRAIN_LOCAL_DIR; do
	got="$(resolved "$v=/tmp/ab-vault-probe")"
	[ "$got" = "/tmp/ab-vault-probe" ] \
		&& t_ok "the runtime honours $v" \
		|| t_bad "$v resolved to '$got'"
done

# --- 2. precedence is newest name first --------------------------------------
# A machine may carry an old spelling in a shell rc for years; the documented
# name has to win over it rather than the other way round.
got="$(resolved AGENTBRAIN_VAULT=/tmp/new AGENTBRAIN_VAULT_DIR=/tmp/mid AGENTBRAIN_LOCAL_DIR=/tmp/old)"
[ "$got" = "/tmp/new" ] && t_ok "AGENTBRAIN_VAULT wins over both older names" || t_bad "precedence gave '$got'"
got="$(resolved AGENTBRAIN_VAULT_DIR=/tmp/mid AGENTBRAIN_LOCAL_DIR=/tmp/old)"
[ "$got" = "/tmp/mid" ] && t_ok "AGENTBRAIN_VAULT_DIR wins over AGENTBRAIN_LOCAL_DIR" || t_bad "precedence gave '$got'"

# --- 3. with none set it still resolves to the checkout ----------------------
got="$(resolved)"   # no overrides at all
case "$got" in
	*/vault|*/local) t_ok "with nothing set it falls back to the checkout" ;;
	*) t_bad "fallback resolved to '$got'" ;;
esac

# --- 4. the installer accepts the runtime spellings too ----------------------
# Same idea from the other side: setup-vault.sh read only AGENTBRAIN_VAULT.
for v in AGENTBRAIN_VAULT AGENTBRAIN_VAULT_DIR AGENTBRAIN_LOCAL_DIR; do
	grep -q "$v" "$ROOT_DIR/scripts/setup/setup-vault.sh" \
		&& t_ok "setup-vault.sh reads $v" \
		|| t_bad "setup-vault.sh ignores $v"
done

if [ "$((pass + fail))" -lt 9 ]; then
	printf 'vault-var-names: only %d assertion(s) ran\n' "$((pass + fail))" >&2; exit 1
fi
printf 'vault-var-names: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
