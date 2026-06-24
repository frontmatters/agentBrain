#!/usr/bin/env bash
# setup-windsurf.sh — Install Windsurf integration.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$(dirname "$0")/agentbrain-pointer.sh"

# Windsurf (Codeium) global rules live at ~/.codeium/windsurf/memories/global_rules.md
# (per docs.windsurf.com — NOT ~/.windsurf/). Detect Windsurf via its config dir, then
# write the global pointer to the path Windsurf actually reads (and uninstall cleans).
WINDSURF_DIR="$AGENT_HOME/.codeium/windsurf"
# Not installed → exit 2 (not applicable). The runner groups all such skips into one line.
if [ ! -d "$WINDSURF_DIR" ] && [ ! -d "$AGENT_HOME/.windsurf" ]; then
	exit 2
fi
WINDSURF_RULES="$WINDSURF_DIR/memories/global_rules.md"
mkdir -p "$(dirname "$WINDSURF_RULES")"

MARKER="agentBrain"
if [ -f "$WINDSURF_RULES" ] && grep -q "${MARKER}" "$WINDSURF_RULES" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    Windsurf (already configured)"
else
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "windsurf.md" >>"$WINDSURF_RULES"
	echo -e "${GREEN}✓${NC} Windsurf"
fi
