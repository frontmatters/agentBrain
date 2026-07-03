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

# Not installed → exit 2 (not applicable), like the other connectors. Presence =
# CLI on PATH or an existing config dir — a standalone run must never scaffold
# a config dir for an absent tool.
if ! command -v claude &>/dev/null && [ ! -d "${CLAUDE_DIR}" ]; then
	exit 2
fi
mkdir -p "${CLAUDE_DIR}"

# Anchored block heading; covers the legacy "# agentBrain" h1 marker too.
if [ -f "${CLAUDE_MD}" ] && grep -qE '^##? agentBrain' "${CLAUDE_MD}" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    Claude Code (already configured)"
else
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "claude.md" >>"${CLAUDE_MD}"
	echo -e "${GREEN}✓${NC} Claude Code"
fi
