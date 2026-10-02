#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Devin Desktop (formerly Windsurf): Devin Local and legacy Cascade pointers.
set -euo pipefail
VAULT="${VAULT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"
# shellcheck source=scripts/agentbrain-pointer.sh
source "$VAULT/scripts/agentbrain-pointer.sh"

# The desktop app is the install marker; neither CLI is necessarily on PATH.
if [ ! -d /Applications/Devin.app ] && [ ! -d "$AGENT_HOME/.config/devin" ] && [ ! -d "$AGENT_HOME/.devin" ]; then
  exit 2
fi
local_rules="$AGENT_HOME/.config/devin/AGENTS.md"
claude_rules="$AGENT_HOME/.claude/CLAUDE.md"
config="$AGENT_HOME/.config/devin/config.json"
# Claude import is enabled by default. An explicit false turns it off.
imports_claude="$(python3 - "$config" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
try:
    cfg = json.loads(p.read_text()) if p.exists() else {}
except (ValueError, OSError):
    # Don't assume import is disabled when configuration is unreadable.
    cfg = {}
read = cfg.get('read_config_from', {})
flag = cfg.get('read_config_from.claude')
if isinstance(read, dict):
    flag = read.get('claude', flag)
print('no' if flag is False else 'yes')
PY
)"
if [ "$imports_claude" = yes ] && [ -f "$claude_rules" ] && \
  [ "$(agentbrain_pointer_state "$claude_rules" "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" claude.md embed)" = current ]; then
  # Older installs may have a redundant Devin block; preserve user rules.
  if [ -f "$local_rules" ]; then agentbrain_pointer_strip "$local_rules"; fi
  echo 'Devin Desktop: Claude import is on and CLAUDE.md has a current pointer; skipping Devin Local pointer to avoid reading agentBrain twice.'
else
  state="$(agentbrain_pointer_sync "$local_rules" "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" devin.md embed)"
  echo "Devin Desktop (Devin Local pointer $state)"
fi

# Cascade continues to consume the old file, but only if it already exists.
cascade="$AGENT_HOME/.codeium/windsurf/memories/global_rules.md"
if [ -f "$cascade" ]; then
  state="$(agentbrain_pointer_sync "$cascade" "${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}" devin.md embed)"
  echo "Devin Desktop (Cascade pointer $state)"
fi
# Remove only our obsolete block, never other legacy user rules.
legacy="$AGENT_HOME/.windsurf/global_rules.md"
if [ -f "$legacy" ]; then agentbrain_pointer_strip "$legacy"; fi
