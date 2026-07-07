#!/usr/bin/env bash
# setup-copilot-cli.sh — Install GitHub Copilot CLI integration.
#
# The GitHub Copilot CLI (the `copilot` command, distinct from the VS Code Copilot
# extension) reads personal global instructions from $HOME/.copilot/copilot-instructions.md
# (per GitHub Docs). Unlike the extension, this is a real file-based mechanism we can write,
# so the brain pointer reaches it automatically. Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$(dirname "$0")/agentbrain-pointer.sh"

COPILOT_DIR="$AGENT_HOME/.copilot"
COPILOT_INSTRUCTIONS="${COPILOT_DIR}/copilot-instructions.md"

# Not installed → exit 2 (not applicable). The runner groups all such skips into one line.
if ! command -v copilot &>/dev/null && [ ! -d "$COPILOT_DIR" ]; then
	exit 2
fi

mkdir -p "$COPILOT_DIR"

# Anchored block heading (Hermes pattern): the bare word "agentBrain" anywhere in
# the file would false-positive on a user's own mention of it.
MARKER="## agentBrain"
if [ -f "$COPILOT_INSTRUCTIONS" ] && grep -q "^${MARKER}" "$COPILOT_INSTRUCTIONS" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    Copilot CLI (already configured)"
else
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "copilot-cli.md" >>"$COPILOT_INSTRUCTIONS"
	echo -e "${GREEN}✓${NC} Copilot CLI"
fi
