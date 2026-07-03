#!/usr/bin/env bash
# setup-hermes.sh — Install Hermes (nousresearch/hermes-agent) integration.
# Safe to re-run (idempotent).
#
# Hermes injects ~/.hermes/SOUL.md into every session (global) and reads
# AGENTS.md/CLAUDE.md from the working directory (per-project). SOUL.md is the
# user's personality file, so we APPEND a marker-guarded pointer block — never
# overwrite. MCP: Hermes reads mcp_servers from ~/.hermes/config.yaml; wiring
# agentbrain-mcp is one CLI command (printed below, not automated — Hermes'
# own `hermes mcp add` flow validates the entry).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$(dirname "$0")/agentbrain-pointer.sh"

HERMES_HOME="${HERMES_HOME:-$AGENT_HOME/.hermes}"
SOUL="${HERMES_HOME}/SOUL.md"

# Not installed → exit 2 (not applicable; the runner groups skips).
command -v hermes >/dev/null 2>&1 || [ -d "$HERMES_HOME" ] || exit 2

mkdir -p "$HERMES_HOME"

MARKER="## agentBrain"
if [ -f "$SOUL" ] && grep -q "^${MARKER}" "$SOUL" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    Hermes (already configured)"
else
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "hermes.md" >>"$SOUL"
	echo -e "${GREEN}✓${NC} Hermes (pointer appended to ${SOUL})"
	echo "  Optional — wire the brain's MCP tools (brain_search/brain_read):"
	echo "    hermes mcp add agentbrain --command bun --args \"${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}/system/addons/agentbrain-mcp/src/server.ts\""
fi
