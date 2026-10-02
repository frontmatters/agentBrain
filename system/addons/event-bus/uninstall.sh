#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# uninstall.sh — inverse of install.sh. Removes the bin/ links install.sh placed in
# $EVENT_BUS_BIN_DIR (default ~/.local/bin), and only links that point back into
# this addon. --purge also removes the runtime state (vault/events/). Idempotent:
# safe to run when nothing exists.
#
#   bash uninstall.sh           # remove the PATH links
#   bash uninstall.sh --purge   # also delete vault/events/ runtime state
set -euo pipefail
ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN="$(cd "$ADDON_DIR/../../.." && pwd)"
# shellcheck source=scripts/lib/vault.sh
. "$BRAIN/scripts/lib/vault.sh"
EVENTS="$VAULT_DIR/events"

bash "$ADDON_DIR/install.sh" --uninstall

if [ "${1:-}" = "--purge" ]; then
	if [ -d "$EVENTS" ]; then
		rm -rf "$EVENTS"
		echo "event-bus: purged runtime state ($EVENTS)."
	else
		echo "event-bus: no runtime state to purge ($EVENTS absent)."
	fi
fi
