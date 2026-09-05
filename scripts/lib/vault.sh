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
# Precedence: AGENTBRAIN_VAULT_DIR (new) > AGENTBRAIN_LOCAL_DIR (the name tests
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
	if [ -n "${AGENTBRAIN_VAULT_DIR:-}" ]; then printf '%s' "$AGENTBRAIN_VAULT_DIR"
	elif [ -n "${AGENTBRAIN_LOCAL_DIR:-}" ]; then printf '%s' "$AGENTBRAIN_LOCAL_DIR"
	elif [ -e "$root/vault" ]; then printf '%s' "$root/vault"
	else printf '%s' "$root/local"   # an install from before the vault/ rename
	fi
}
VAULT_DIR="$(vault_dir)"; export VAULT_DIR
