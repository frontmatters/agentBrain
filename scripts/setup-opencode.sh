#!/usr/bin/env bash
# setup-opencode.sh — Install OpenCode integration.
# Safe to re-run (idempotent).
#
# OpenCode reads instruction file paths from the `instructions` array in
# ~/.config/opencode/opencode.json. We write the canonical pointer block (from
# agentbrain-pointer.sh) to ~/.config/opencode/agentbrain-pointer.md and register
# that path in the array — merging into the existing config, never overwriting.
# uninstall.sh removes both symmetrically.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# shellcheck source=scripts/agentbrain-pointer.sh
source "$(dirname "$0")/agentbrain-pointer.sh"

OPENCODE_DIR="$AGENT_HOME/.config/opencode"
OPENCODE_JSON="${OPENCODE_DIR}/opencode.json"
POINTER_FILE="${OPENCODE_DIR}/agentbrain-pointer.md"

# Not installed → exit 2 (not applicable). Presence = CLI on PATH or an existing
# config dir (current ~/.config/opencode or legacy ~/.opencode).
if ! command -v opencode &>/dev/null && [ ! -d "$OPENCODE_DIR" ] && [ ! -d "$AGENT_HOME/.opencode" ]; then
	exit 2
fi

# Already configured = pointer file exists AND is registered in the instructions array.
if [ -f "$POINTER_FILE" ] && [ -f "$OPENCODE_JSON" ] && grep -q "agentbrain-pointer.md" "$OPENCODE_JSON" 2>/dev/null; then
	echo -e "${YELLOW}Skip${NC}    OpenCode (already configured)"
else
	mkdir -p "$OPENCODE_DIR"
	agentbrain_pointer_block "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" "opencode.md" >"$POINTER_FILE"
	# Merge the pointer path into the instructions array. Errors stay visible and
	# fail the script (the runner reports it), so a malformed user config is never
	# silently skipped or overwritten.
	python3 - "$OPENCODE_JSON" "$POINTER_FILE" <<'PY'
import json, sys
from pathlib import Path

config_path = Path(sys.argv[1])
pointer = sys.argv[2]

config = {}
if config_path.exists():
    try:
        config = json.loads(config_path.read_text())
    except json.JSONDecodeError as e:
        sys.stderr.write(
            f"setup-opencode: cannot parse {config_path} as JSON: {e}\n"
            "  Fix the file (or move it aside) and re-run.\n")
        sys.exit(1)

instructions = config.get('instructions', [])
if not isinstance(instructions, list):
    sys.stderr.write(
        f"setup-opencode: 'instructions' in {config_path} is not an array — "
        "fix it manually and re-run.\n")
    sys.exit(1)

if pointer not in instructions:
    instructions.append(pointer)
config['instructions'] = instructions

config_path.write_text(json.dumps(config, indent=2) + '\n')
PY
	echo -e "${GREEN}✓${NC} OpenCode"
fi
