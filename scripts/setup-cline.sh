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
CLINE_RULES="${CLINE_DIR}/Rules/.clinerules"

# Not installed → exit 2 (not applicable). The runner groups all such skips into one
# line, so per-client scripts stay silent when their target is absent.
[ -d "${CLINE_DIR}" ] || exit 2

mkdir -p "$(dirname "$CLINE_RULES")"

MARKER="agentBrain"
if [ -f "$CLINE_RULES" ] && grep -q "${MARKER}" "$CLINE_RULES" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    Cline (already configured)"
else
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "cline.md" >"$CLINE_RULES"
	echo -e "${GREEN}✓${NC} Cline"
fi
