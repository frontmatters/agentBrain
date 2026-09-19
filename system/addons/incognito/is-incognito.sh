#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# is-incognito.sh — single source of truth for "is this session incognito?".
# Exit 0 if incognito mode is active (flag file present), 1 otherwise.
#
# The flag lives in the ACTIVE vault so it flips with `brain use dev|live`:
#   <vault>/local/sessions/.incognito
# This path is the CANONICAL definition. The agentbrain-mcp server mirrors it in
# src/write.ts (INCOGNITO_FLAG) for its own write guard — keep both in sync.
#
# Resolution is shared with every other Bash consumer through vault.sh.
# Robust by construction: never errors out, only ever reports 0/1.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || exit 1
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=scripts/lib/vault.sh
. "$BRAIN_ROOT/scripts/lib/vault.sh"

[ -f "$VAULT_DIR/sessions/.incognito" ] && exit 0
exit 1
