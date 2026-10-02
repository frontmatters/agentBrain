#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup-cline.sh — Install Cline integration.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$VAULT/scripts/agentbrain-pointer.sh"

CLINE_DIR="$AGENT_HOME/Documents/Cline"
# Cline reads EVERY file in Rules/, so we write our own file and never touch the
# user's .clinerules (the old setup `>`-overwrote it, destroying user rules).
CLINE_RULES="${CLINE_DIR}/Rules/agentBrain.md"

# Not installed → exit 2 (not applicable). The runner groups all such skips into one
# line, so per-client scripts stay silent when their target is absent.
[ -d "${CLINE_DIR}" ] || exit 2

mkdir -p "$(dirname "$CLINE_RULES")"
# Refresh the managed block without changing the user's surrounding text.
state="$(agentbrain_pointer_sync "$CLINE_RULES" "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "cline.md" own)"
echo -e "${GREEN}✓${NC} Cline (pointer $state)"
