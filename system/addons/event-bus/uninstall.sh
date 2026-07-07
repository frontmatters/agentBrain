#!/usr/bin/env bash
# uninstall.sh — inverse of install.sh. event-bus installs nothing outside its own
# dir, so by default there is nothing to undo. --purge removes the runtime state
# (local/events/). Idempotent: safe to run when nothing exists.
#
#   bash uninstall.sh           # report-only (nothing was installed)
#   bash uninstall.sh --purge   # also delete local/events/ runtime state
set -euo pipefail
ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN="$(cd "$ADDON_DIR/../../.." && pwd)"
EVENTS="$BRAIN/local/events"

if [ "${1:-}" = "--purge" ]; then
	if [ -d "$EVENTS" ]; then
		rm -rf "$EVENTS"
		echo "event-bus: purged runtime state ($EVENTS)."
	else
		echo "event-bus: no runtime state to purge ($EVENTS absent)."
	fi
	exit 0
fi

echo "event-bus: nothing installed outside the addon dir — nothing to remove."
echo "  Runtime state (if any) is in $EVENTS; remove it with: bash $0 --purge"
