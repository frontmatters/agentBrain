#!/usr/bin/env bash
# setup-cursor.sh — Guide Cursor integration.
#
# Why this prints guidance instead of writing a setting:
# Cursor does not run the Copilot extension, so `github.copilot.*` keys in Cursor's
# settings.json are a no-op. Cursor reads its own Rules — User Rules (Settings > Rules,
# stored in an app-internal DB, not reliably scriptable) or project rules
# (`.cursor/rules/*.mdc` / legacy `.cursorrules`). We point the user at those instead
# of mutating a settings key the tool ignores.
# Safe to re-run (no state).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"
BRAIN="${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}"

CYAN='\033[0;36m'
NC='\033[0m'

# Cursor not found → exit 2 (not applicable). The runner groups all such skips into one line.
if ! command -v cursor &>/dev/null \
	&& [ ! -d "$AGENT_HOME/Library/Application Support/Cursor/User" ] \
	&& [ ! -d "$AGENT_HOME/.config/Cursor/User" ]; then
	exit 2
fi

echo -e "${CYAN}Cursor — manual step${NC} (Cursor uses its own Rules, not Copilot settings)"
echo "  • Global: Settings > Rules > User Rules — add a thin pointer to ${BRAIN}/system/rules.md"
echo "  • Per project: a .cursor/rules/agentBrain.mdc (or legacy .cursorrules) with the same pointer."
echo "  Details: ${VAULT}/system/agent-config/cursor.md"
