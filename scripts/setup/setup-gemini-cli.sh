#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-gemini-cli.sh — Install Gemini CLI integration.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$VAULT/scripts/agentbrain-pointer.sh"

GEMINI_DIR="$AGENT_HOME/.gemini"
GEMINI_MD="${GEMINI_DIR}/GEMINI.md"

# Not installed → exit 2 (not applicable), like the other connectors. Presence =
# CLI on PATH or an existing config dir — a standalone run must never scaffold
# a config dir for an absent tool.
if ! command -v gemini &>/dev/null && [ ! -d "${GEMINI_DIR}" ]; then
	exit 2
fi
mkdir -p "${GEMINI_DIR}"

# Refresh the managed block without changing the user's surrounding text.
state="$(agentbrain_pointer_sync "$GEMINI_MD" "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "gemini.md" embed)"
echo -e "${GREEN}✓${NC} Gemini CLI (pointer $state)"
