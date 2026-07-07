#!/usr/bin/env bash
# setup-copilot.sh — Guide VS Code Copilot integration.
#
# Why this prints guidance instead of writing a setting:
# Copilot reads custom instructions from FILES, not a settings.json key. The old
# `github.copilot.advanced.instructions` string was a no-op — it is not a documented
# key, and settings-based code-generation instructions are deprecated as of VS Code
# 1.102. The working mechanisms are file-based: per-workspace `.github/copilot-instructions.md`,
# `AGENTS.md`, or `CLAUDE.md` (auto-read at a repo root), or a user-level
# `*.instructions.md` with `applyTo: '**'` for a global pointer. We point the user at
# those instead of mutating settings.json with a key the tool ignores.
# See: https://code.visualstudio.com/docs/copilot/customization/custom-instructions
# Safe to re-run (no state).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"
BRAIN="${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}"

CYAN='\033[0;36m'
NC='\033[0m'

# VS Code not found → exit 2 (not applicable). The runner groups all such skips into one line.
if ! command -v code &>/dev/null \
	&& [ ! -d "$AGENT_HOME/Library/Application Support/Code/User" ] \
	&& [ ! -d "$AGENT_HOME/.config/Code/User" ] \
	&& [ ! -d "$AGENT_HOME/.config/Code - Insiders/User" ]; then
	exit 2
fi

echo -e "${CYAN}Copilot (VS Code) — manual step${NC} (Copilot reads instruction files, not a setting)"
echo "  • Per project: a repo's .github/copilot-instructions.md, AGENTS.md, or CLAUDE.md is read automatically."
echo "  • Global (all projects): add a user instruction file, e.g."
echo "      ~/Library/Application Support/Code/User/prompts/agentBrain.instructions.md"
echo "    with frontmatter \"applyTo: '**'\" that points to ${BRAIN}/system/rules.md"
echo "  Details: ${VAULT}/system/agent-config/vscode-copilot.md"
