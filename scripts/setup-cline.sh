#!/usr/bin/env bash
# setup-cline.sh — Install Cline integration.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$(dirname "$0")/agentbrain-pointer.sh"

CLINE_DIR="$AGENT_HOME/Documents/Cline"
# Cline reads EVERY file in Rules/, so we write our own file and never touch the
# user's .clinerules (the old setup `>`-overwrote it, destroying user rules).
CLINE_RULES="${CLINE_DIR}/Rules/agentBrain.md"

# Not installed → exit 2 (not applicable). The runner groups all such skips into one
# line, so per-client scripts stay silent when their target is absent.
[ -d "${CLINE_DIR}" ] || exit 2

# Already configured = our own rules file exists.
if [ -f "$CLINE_RULES" ]; then
	echo -e "${YELLOW}Skip${NC}    Cline (already configured)"
else
	mkdir -p "$(dirname "$CLINE_RULES")"
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "cline.md" >"$CLINE_RULES"
	echo -e "${GREEN}✓${NC} Cline"
fi
