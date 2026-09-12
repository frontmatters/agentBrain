#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install/activate the claude-memory-redirect addon.
# Locale: auto-detected from $LANG, override with AGENTBRAIN_LOCALE=nl|en.
#
# What it does (always):
#   1. Ensures local config exists (seeded from default)
#   2. Makes scripts executable
#   3. Runs claude-memory-migrate.sh for the current project (idempotent)
#   4. Verifies the CLAUDE.md instruction block is in place (warns if missing)
#
# Mode-dependent:
#   - symlink   → runs claude-memory-symlink.sh for current project
#   - sync_hook → ensures PostToolUse hook is in ~/.claude/settings.json
#   - instruction_only → does nothing extra at the file level
#   - disabled  → does nothing
#
# Pass --all to apply migrate/symlink to every project.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
LOCAL_CONFIG="$BRAIN_ROOT/vault/memories/claude-redirect-config.json"
DEFAULT_CONFIG="$HERE/config.default.json"
SETTINGS="$HOME/.claude/settings.json"

source "$BRAIN_ROOT/scripts/lib/_strings.sh"

all_flag=""
[[ "${1:-}" == "--all" ]] && all_flag="--all"

mkdir -p "$BRAIN_ROOT/vault/memories/projects"
chmod +x "$HERE"/*.sh

if [[ ! -f "$LOCAL_CONFIG" ]]; then
	cp "$DEFAULT_CONFIG" "$LOCAL_CONFIG"
	echo "✓ $(t install.cmr.seeded) $LOCAL_CONFIG"
else
	echo "• $(t install.cmr.config_exists)"
fi

mode="$(python3 -c "
import json
try:
    c = json.load(open('$LOCAL_CONFIG'))
    print(c.get('mode','symlink') if c.get('enabled',True) else 'disabled')
except Exception:
    print('symlink')
" 2>/dev/null || echo symlink)"

echo "▸ $(t install.cmr.active_mode) $mode"

echo ""
echo "── $(t install.cmr.section_migrate) ──"
AGENTBRAIN_LOCALE="$_AGENTBRAIN_LOCALE" bash "$HERE/claude-memory-migrate.sh" $all_flag || true

echo ""
echo "── $(t install.cmr.section_activation) ──"
case "$mode" in
	symlink)
		AGENTBRAIN_LOCALE="$_AGENTBRAIN_LOCALE" bash "$HERE/claude-memory-symlink.sh" $all_flag || true
		;;
	sync_hook)
		hook_path="$HERE/claude-memory-sync-hook.sh"
		if ! grep -q "$(basename "$hook_path")" "$SETTINGS" 2>/dev/null; then
			echo "⚠️  $(t install.cmr.sync_hook_register)"
			cat <<EOF
{
  "matcher": "Write|Edit|MultiEdit",
  "hooks": [
    {"type": "command", "command": "$hook_path"}
  ]
}
EOF
		else
			echo "✓ $(t install.cmr.sync_hook_present)"
		fi
		;;
	instruction_only)
		echo "• $(t install.cmr.mode_instruction_only)"
		;;
	disabled)
		echo "• $(t install.cmr.mode_disabled)"
		;;
	*)
		echo "⚠️  $(t install.cmr.unknown_mode) $mode" >&2 ;;
esac

echo ""
echo "── $(t install.cmr.section_claudemd) ──"
if grep -q "Memory — alleen via agentBrain\|Memory — agentBrain only" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
	echo "✓ $(t install.cmr.claudemd_present)"
else
	echo "⚠️  $(t install.cmr.claudemd_missing)"
fi

echo ""
echo "$(t install.cmr.done)"
