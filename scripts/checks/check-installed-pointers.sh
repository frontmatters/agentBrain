#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Read-only user health light for installed client pointers.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/agentbrain-pointer.sh
source "$ROOT/scripts/agentbrain-pointer.sh"
BASE="${AGENTBRAIN_HOME:-$HOME}"
BRAIN="${BRAIN_ALIAS:-$BASE/agentBrain}"
# A light that can turn red: any installed pointer that is not current, or that
# names a file that is gone, makes the check fail with its fix command.
problems=0
check() {
 local label="$1" setup="$2" file="$3" config="$4" mode="$5" state dead
 [ -f "$file" ] || return 0
 state="$(agentbrain_pointer_state "$file" "$BRAIN" "$config" "$mode")"
 # Only inspect the pointer, not unrelated user prose. Count explicit absolute
 # paths below the alias; optional directory references are not dead files.
 dead="$(python3 - "$file" "$BRAIN" "$mode" <<'PY'
import os, re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
brain, mode = sys.argv[2:]
if mode == 'embed':
    # every agentBrain block counts: old installs could hold more than one
    blocks = re.findall(r'(?ms)^<!-- agentBrain:begin -->\n.*?^<!-- agentBrain:end -->', text)
    rest = re.sub(r'(?ms)^<!-- agentBrain:begin -->\n.*?^<!-- agentBrain:end -->', '', text)
    blocks += re.findall(r'(?ms)^##? agentBrain\b.*?(?=^## |\Z)', rest)
    text = '\n'.join(blocks)
paths = re.findall(r'`(' + re.escape(brain) + r'/[^`\s]+)`', text)
print(sum(not os.path.exists(p) for p in paths if '<' not in p and not p.endswith('/')))
PY
)"
 echo "  $label: $state, $dead dead reference(s)"
 if [ "$state" != current ] || [ "$dead" -gt 0 ]; then
  echo "    Fix: bash $BRAIN/scripts/setup/setup-$setup.sh"
  problems=$((problems + 1))
 fi
}
check 'Claude Code' claude-code "$BASE/.claude/CLAUDE.md" claude.md embed
check 'Gemini CLI' gemini-cli "$BASE/.gemini/GEMINI.md" gemini.md embed
check 'Copilot CLI' copilot-cli "$BASE/.copilot/copilot-instructions.md" copilot-cli.md embed
check 'Hermes' hermes "${HERMES_HOME:-$BASE/.hermes}/SOUL.md" hermes.md embed
# Claude-imported Devin Local rules do not need a second block.
if [ -f "$BASE/.config/devin/AGENTS.md" ] && grep -qE '^##? agentBrain|^<!-- agentBrain:begin -->' "$BASE/.config/devin/AGENTS.md"; then
 check 'Devin Desktop' devin "$BASE/.config/devin/AGENTS.md" devin.md embed
fi
check 'Devin Desktop Cascade' devin "$BASE/.codeium/windsurf/memories/global_rules.md" devin.md embed
check 'Cline' cline "$BASE/Documents/Cline/Rules/agentBrain.md" cline.md own
check 'OpenCode' opencode "$BASE/.config/opencode/agentbrain-pointer.md" opencode.md own
if [ "$problems" -gt 0 ]; then
 echo "check-installed-pointers: $problems client pointer(s) need the fix above"
 exit 1
fi
echo 'check-installed-pointers: every installed client pointer is current'
