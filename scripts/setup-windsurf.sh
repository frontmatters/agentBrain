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

# Windsurf (Codeium) global rules live at <config-root>/memories/global_rules.md.
# The classic root is ~/.codeium/windsurf (per docs.windsurf.com); newer installs
# may use ~/.windsurf. Write into the root that actually EXISTS (preferring the
# classic one when both do) — never scaffold ~/.codeium for a ~/.windsurf install.
# uninstall.sh cleans both candidates.
if [ -d "$AGENT_HOME/.codeium/windsurf" ]; then
	WINDSURF_DIR="$AGENT_HOME/.codeium/windsurf"
elif [ -d "$AGENT_HOME/.windsurf" ]; then
	WINDSURF_DIR="$AGENT_HOME/.windsurf"
else
	# Not installed → exit 2 (not applicable). The runner groups all such skips into one line.
	exit 2
fi
WINDSURF_RULES="$WINDSURF_DIR/memories/global_rules.md"
mkdir -p "$(dirname "$WINDSURF_RULES")"

# Anchored block heading (Hermes pattern): the bare word "agentBrain" anywhere in
# the file would false-positive on a user's own mention of it.
MARKER="## agentBrain"
if [ -f "$WINDSURF_RULES" ] && grep -q "^${MARKER}" "$WINDSURF_RULES" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    Windsurf (already configured)"
else
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "windsurf.md" >>"$WINDSURF_RULES"
	echo -e "${GREEN}✓${NC} Windsurf"
fi
