#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-claude-code.sh — Install Claude Code integration.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$VAULT/scripts/agentbrain-pointer.sh"

CLAUDE_DIR="$AGENT_HOME/.claude"
CLAUDE_MD="${CLAUDE_DIR}/CLAUDE.md"

# A config directory alone does not prove that Claude Code is installed: macOS
# users and test harnesses can create ~/.claude independently. Only the CLI is
# an installation signal; report an existing directory separately.
if ! command -v claude &>/dev/null; then
	if [ -d "${CLAUDE_DIR}" ]; then
		echo -e "${YELLOW}Skip${NC}    Claude Code (CLI not detected; config directory exists)"
	fi
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
