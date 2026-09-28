#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# vault.sh — the one place that says where the vault is.
#
# The vault is a directory outside the checkout (~/.agentBrain/vault by
# default), reached through a symlink in the checkout root. That link was
# called local/ for a long time and is called vault/ now; local/ stays as an
# alias until nothing uses it. Thirteen scripts each carried their own
# definition, in five spellings, before this file existed. One definition,
# sourced everywhere, is how a rename becomes one line instead of a thousand.
#
# Precedence: AGENTBRAIN_VAULT (what the installer documents) >
# AGENTBRAIN_VAULT_DIR > AGENTBRAIN_LOCAL_DIR (the name tests
# and callers used before) > <checkout>/vault > <checkout>/local (a checkout
# that setup has not touched since the rename).
#
# Note ids are NOT affected by any of this: uuid5-gen.sh hashes the spelling
# "local/<path>" as a namespace token whatever the directory is called.
#
# Usage:  source "$ROOT/scripts/lib/vault.sh"      # defines VAULT_DIR
#         vault_dir                                # prints it
vault_dir() {
	local root
	root="${AGENTBRAIN_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
	# AGENTBRAIN_VAULT is the name the installer documents and the one a user
	# sets by hand (`--vault=PATH / AGENTBRAIN_VAULT=PATH`). It was read only by
	# setup-vault.sh, so setting it moved where the vault was CREATED and not
	# where the runtime LOOKED: one spelling for the install, another for every
	# script afterwards. All three resolve here now, newest name first.
	if [ -n "${AGENTBRAIN_VAULT:-}" ]; then printf '%s' "$AGENTBRAIN_VAULT"
	elif [ -n "${AGENTBRAIN_VAULT_DIR:-}" ]; then printf '%s' "$AGENTBRAIN_VAULT_DIR"
	elif [ -n "${AGENTBRAIN_LOCAL_DIR:-}" ]; then printf '%s' "$AGENTBRAIN_LOCAL_DIR"
	elif [ -e "$root/vault" ]; then printf '%s' "$root/vault"
	else printf '%s' "$root/local"   # an install from before the vault/ rename
	fi
}
VAULT_DIR="$(vault_dir)"; export VAULT_DIR

# vault_required — assert the vault is actually reachable before you measure it.
#
# vault_dir() answers WHERE, never WHETHER. Its last branch falls back to
# <checkout>/local, which need not exist, so VAULT_DIR can point at nothing and
# every caller proceeds as if it had looked. A check that counts vault content
# then reports zero findings and exits 0: green because it saw nothing, not
# because there was nothing to see. The full doctor is safe (check-anchors
# fails on a missing vault); a single check run by hand, which is how a
# targeted fix gets validated, is not.
#
# Usage:  vault_required "check-enforcement" || exit $?
#         vault_required "check-nda" "$VAULT" || exit $?   # assert a given path
#
# A consumer checkout legitimately has NO vault until setup.sh has run, so a
# missing vault is a third state, "not measured", distinct from pass and fail;
# doctor counts it separately. Callers only need a non-zero exit to mean "do not
# report a result".
# Exit 0 = measured, 1 = a vault was promised and is unreachable, 77 = no vault
# in this checkout at all, so nothing was measured and nothing is claimed.
#
# 77 and not 2: `exit 2` already means "bad argument" in fifteen checks and
# `exit 3` in two, so the doctor would have relabelled an option typo as
# "not measured". 77 is the automake skip convention and is unused here.
# It collides with EX_NOPERM in sysexits.h, where 77 means permission denied.
# Nothing in this repo reads sysexits and the shell-test convention is much the
# stronger reading, so the collision is accepted deliberately: it is written
# down here so nobody spends an afternoon hunting a permission problem.
vault_required() {
	local caller="${1:?vault_required needs the caller name for its message}"
	local root v
	root="${AGENTBRAIN_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
	# A caller that already resolved its own vault passes it; otherwise ask the lib.
	v="${2:-$(vault_dir)}"
	[ -d "$v" ] && return 0
	# Someone asserted a vault: an env override names one, or a link in the
	# checkout points at one. Absence is then a fault, not a starting state.
	if [ -n "${AGENTBRAIN_VAULT:-}${AGENTBRAIN_VAULT_DIR:-}${AGENTBRAIN_LOCAL_DIR:-}" ] \
		|| [ -L "$root/vault" ] || [ -L "$root/local" ]; then
		echo "FAIL $caller: a vault is declared at '$v' but it is not readable." >&2
		echo "  -> a promised vault that is gone is worse than none: the check would pass on an empty tree." >&2
		return 1
	fi
	echo "SKIP $caller: no vault in this checkout, so nothing was measured." >&2
	echo "  -> this is the state before scripts/setup/setup.sh has run; not a pass." >&2
	return 77
}
