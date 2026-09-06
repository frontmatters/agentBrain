#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-launchd-lan.sh — install/uninstall the two LAN launchd agents of a
# factory host: the git daemon that exports the dev checkout over the LAN and
# the lan-install job. Both templates live in system/launchd/ and were rendered
# by hand until now, which is how they kept logging to local/logs/ after the
# vault rename. Safe to re-run (idempotent: unloads before re-loading).
#
# Usage:
#   bash scripts/setup/setup-launchd-lan.sh                # render + bootstrap both
#   bash scripts/setup/setup-launchd-lan.sh --uninstall    # unload + remove both
#
# macOS only. Other platforms: exit 2 (not applicable).
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "setup-launchd-lan: macOS only — skip"
	exit 2
fi

VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"
LABELS="dev.agentbrain.git-daemon dev.agentbrain.lan-install"
LOGS_DIR="${VAULT}/vault/logs"
TARGET_DOMAIN="gui/$(id -u)"

UNINSTALL=false
for arg in "$@"; do
	case "$arg" in
		--uninstall) UNINSTALL=true ;;
		*) echo "Unknown arg: $arg" >&2; exit 2 ;;
	esac
done

for LABEL in $LABELS; do
	PLIST_TEMPLATE="${VAULT}/system/launchd/${LABEL}.plist.template"
	PLIST_PATH="${AGENT_HOME}/Library/LaunchAgents/${LABEL}.plist"

	if launchctl print "${TARGET_DOMAIN}/${LABEL}" >/dev/null 2>&1; then
		launchctl bootout "${TARGET_DOMAIN}/${LABEL}" 2>/dev/null || true
		[ "$UNINSTALL" = true ] && echo "✓ Unloaded ${LABEL}"
	fi
	if [ "$UNINSTALL" = true ]; then
		if [ -f "$PLIST_PATH" ]; then
			rm "$PLIST_PATH"
			echo "✓ Removed ${PLIST_PATH}"
		fi
		continue
	fi

	if [ ! -f "$PLIST_TEMPLATE" ]; then
		echo "setup-launchd-lan: template missing: $PLIST_TEMPLATE" >&2
		exit 1
	fi
	mkdir -p "$(dirname "$PLIST_PATH")" "$LOGS_DIR"
	# Render: {{VAULT}} is the checkout, {{HOME}} the agent home.
	sed -e "s|{{VAULT}}|${VAULT}|g" -e "s|{{HOME}}|${AGENT_HOME}|g" "$PLIST_TEMPLATE" > "$PLIST_PATH"
	launchctl bootstrap "$TARGET_DOMAIN" "$PLIST_PATH"
	echo "✓ Loaded ${LABEL}, logs in ${LOGS_DIR}"
done
