#!/usr/bin/env bash
# setup-launchd-loop.sh — install/uninstall the agentBrain self-improving-loop
# launchd agent (Phase 5: autonomous trigger). Safe to re-run (idempotent —
# unloads existing before re-loading).
#
# Usage:
#   bash scripts/setup-launchd-loop.sh                # install + bootstrap
#   bash scripts/setup-launchd-loop.sh --uninstall    # remove
#   bash scripts/setup-launchd-loop.sh --kickstart    # install + fire once now
#
# macOS only. Other platforms: exit 2 (not applicable).

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "setup-launchd-loop: macOS only — skip"
	exit 2
fi

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"
LABEL="dev.agentbrain.loop"
PLIST_TEMPLATE="${VAULT}/system/launchd/${LABEL}.plist.template"
PLIST_PATH="${AGENT_HOME}/Library/LaunchAgents/${LABEL}.plist"
LOGS_DIR="${VAULT}/local/logs"  # in-brain logs (per connector model — brain content lives in brain)

UNINSTALL=false
KICKSTART=false
for arg in "$@"; do
	case "$arg" in
		--uninstall) UNINSTALL=true ;;
		--kickstart) KICKSTART=true ;;
		*) echo "Unknown arg: $arg" >&2; exit 2 ;;
	esac
done

UID_NUMERIC="$(id -u)"
TARGET_DOMAIN="gui/${UID_NUMERIC}"

if [ "$UNINSTALL" = true ]; then
	if launchctl print "${TARGET_DOMAIN}/${LABEL}" >/dev/null 2>&1; then
		launchctl bootout "${TARGET_DOMAIN}/${LABEL}" 2>/dev/null || true
		echo "✓ Unloaded ${LABEL}"
	fi
	if [ -f "$PLIST_PATH" ]; then
		rm "$PLIST_PATH"
		echo "✓ Removed ${PLIST_PATH}"
	fi
	exit 0
fi

if [ ! -f "$PLIST_TEMPLATE" ]; then
	echo "setup-launchd-loop: template missing: $PLIST_TEMPLATE" >&2
	exit 1
fi

mkdir -p "$(dirname "$PLIST_PATH")" "$LOGS_DIR"

# Render template — substitute {{VAULT}} and {{HOME}} with actual paths.
sed -e "s|{{VAULT}}|${VAULT}|g" -e "s|{{HOME}}|${AGENT_HOME}|g" "$PLIST_TEMPLATE" > "$PLIST_PATH"

# Validate before loading — plutil -lint reports XML/plist errors with line numbers.
if ! plutil -lint "$PLIST_PATH" >/dev/null; then
	echo "setup-launchd-loop: rendered plist failed plutil -lint:" >&2
	plutil -lint "$PLIST_PATH" >&2
	exit 1
fi

# Idempotent reload: bootout if already loaded, then bootstrap.
if launchctl print "${TARGET_DOMAIN}/${LABEL}" >/dev/null 2>&1; then
	launchctl bootout "${TARGET_DOMAIN}/${LABEL}" 2>/dev/null || true
fi
launchctl bootstrap "$TARGET_DOMAIN" "$PLIST_PATH"
echo "✓ Loaded ${LABEL} → daily at 04:00, logs in ${LOGS_DIR}/loop-tick.{out,err}.log"

if [ "$KICKSTART" = true ]; then
	launchctl kickstart -k "${TARGET_DOMAIN}/${LABEL}"
	echo "✓ Kickstarted once — check ${LOGS_DIR}/loop-tick.out.log for output"
fi
