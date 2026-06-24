#!/usr/bin/env bash
# setup-gemini-cli.sh — Install Gemini CLI integration.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$(dirname "$0")/agentbrain-pointer.sh"

GEMINI_DIR="$AGENT_HOME/.gemini"
GEMINI_MD="${GEMINI_DIR}/GEMINI.md"

if [ ! -d "${GEMINI_DIR}" ]; then
	mkdir -p "${GEMINI_DIR}"
	echo -e "${GREEN}Created${NC} ~/.gemini/"
fi

MARKER="agentBrain"
if [ -f "${GEMINI_MD}" ] && grep -q "${MARKER}" "${GEMINI_MD}" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    Gemini CLI (already configured)"
else
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "gemini.md" >>"${GEMINI_MD}"
	echo -e "${GREEN}✓${NC} Gemini CLI"
fi
