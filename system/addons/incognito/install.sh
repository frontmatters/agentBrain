#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install/refresh the incognito addon: make scripts executable and verify that the
# PreToolUse guard is wired into Claude Code settings. Idempotent; never destructive.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"

chmod +x "$HERE"/*.sh "$HERE"/bin/* 2>/dev/null || true
mkdir -p "$BRAIN_ROOT/vault/sessions"

GUARD="$HERE/claude-pretooluse-guard.sh"
BANNER="$HERE/session-banner.sh"
SETTINGS="$HOME/.claude/settings.json"

if [[ -f "$SETTINGS" ]]; then
	if grep -q 'incognito/claude-pretooluse-guard.sh' "$SETTINGS"; then
		echo "✓ PreToolUse guard registered in $SETTINGS"
	else
		echo "⚠️  PreToolUse guard NOT registered. Add to hooks.PreToolUse in $SETTINGS:"
		echo "    matcher: Write|Edit|MultiEdit"
		echo "    command: $GUARD"
	fi
	if grep -q 'incognito/session-banner.sh' "$SETTINGS"; then
		echo "✓ SessionStart banner registered in $SETTINGS"
	else
		echo "⚠️  SessionStart banner NOT registered. Add to hooks.SessionStart in $SETTINGS:"
		echo "    matcher: *"
		echo "    command: $BANNER"
	fi
else
	echo "⚠️  no $SETTINGS — Claude Code config missing"
fi

echo
echo "incognito installed. Toggle with /incognito on|off|status"
