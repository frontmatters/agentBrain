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
# Resolution order (alias-aware first, own-tree fallback so it works even when
# called via a path that isn't the alias):
#   1. $AGENTBRAIN_HOME/agentBrain  (or $HOME/agentBrain) — the live alias
#   2. this script's own brain root ($HERE/../../..)
#
# Robust by construction: never errors out, only ever reports 0/1.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || exit 1

for root in "${AGENTBRAIN_HOME:-$HOME}/agentBrain" "$HERE/../../.."; do
	if [ -f "$root/vault/sessions/.incognito" ]; then
		exit 0
	fi
done
exit 1
