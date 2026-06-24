#!/usr/bin/env bash
# setup-opencode.sh — Install OpenCode integration.
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

OPENCODE_CONFIG="$AGENT_HOME/.opencode/opencode.json"

# Not installed → exit 2 (not applicable). The runner groups all such skips into one line.
[ -d "$(dirname "$OPENCODE_CONFIG")" ] || exit 2

MARKER="agentBrain"
if [ -f "$OPENCODE_CONFIG" ] && grep -q "${MARKER}" "$OPENCODE_CONFIG" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    OpenCode (already configured)"
else
	python3 <<PY
import json
from pathlib import Path

vault = "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}"
config_path = Path("${OPENCODE_CONFIG}")

# Create config if it doesn't exist
if not config_path.exists():
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config = {}
else:
    with open(config_path, 'r') as f:
        config = json.load(f)

# Add agentBrain instructions
config['system_prompt'] = config.get('system_prompt', '')
config['system_prompt'] += f"""

# agentBrain
# Persistent knowledge base at {vault}
# Read these at session start:
# - {vault}/learnings/patterns.md
# - {vault}/learnings/troubleshooting.md
# - {vault}/system/rules.md
"""

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
PY
	echo -e "${GREEN}✓${NC} OpenCode"
fi
