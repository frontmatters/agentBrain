#!/usr/bin/env bash
# Install/refresh the session-journal addon.
# Locale: auto-detected from $LANG, override with AGENTBRAIN_LOCALE=nl|en.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
LOCAL_CONFIG="$BRAIN_ROOT/local/sessions/journal-config.json"
DEFAULT_CONFIG="$HERE/config.default.json"

# i18n
source "$BRAIN_ROOT/scripts/lib/_strings.sh"

mkdir -p "$BRAIN_ROOT/local/sessions"
chmod +x "$HERE"/*.sh

if [[ ! -f "$LOCAL_CONFIG" ]]; then
	cp "$DEFAULT_CONFIG" "$LOCAL_CONFIG"
	echo "✓ $(t install.sj.seeded) $LOCAL_CONFIG"
else
	echo "• $(t install.sj.config_exists) $LOCAL_CONFIG"
fi

SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$SETTINGS" ]]; then
	if grep -q 'session-journal/claude-stop-hook.sh' "$SETTINGS" \
	  && grep -q 'session-journal/claude-autosave-hook.sh' "$SETTINGS"; then
		echo "✓ $(t install.sj.hooks_registered) $SETTINGS"
	else
		echo "⚠️  $(t install.sj.hooks_missing)"
		echo "   Stop:        $HERE/claude-stop-hook.sh"
		echo "   PostToolUse: $HERE/claude-autosave-hook.sh  (matcher: Write|Edit|MultiEdit)"
	fi
else
	echo "⚠️  no $SETTINGS — Claude Code config missing"
fi

SLASH="$HOME/.claude/commands/journal.md"
if [[ -f "$SLASH" ]]; then
	echo "✓ $(t install.sj.slash_present) $SLASH"
else
	echo "⚠️  $(t install.sj.slash_missing) $SLASH"
fi

echo
echo "$(t install.sj.done)"
