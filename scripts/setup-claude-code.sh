#!/usr/bin/env bash
# setup-claude-code.sh — Install Claude Code integration.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$(dirname "$0")/agentbrain-pointer.sh"

CLAUDE_DIR="$AGENT_HOME/.claude"
CLAUDE_MD="${CLAUDE_DIR}/CLAUDE.md"

if [ ! -d "${CLAUDE_DIR}" ]; then
	mkdir -p "${CLAUDE_DIR}"
	echo -e "${GREEN}Created${NC} ~/.claude/"
fi

MARKER="# agentBrain"
if [ -f "${CLAUDE_MD}" ] && grep -q "${MARKER}" "${CLAUDE_MD}" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    Claude Code (already configured)"
else
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "claude.md" >>"${CLAUDE_MD}"
	echo -e "${GREEN}✓${NC} Claude Code"
fi
