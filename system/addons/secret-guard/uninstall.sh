#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || exit 0
COMMAND="python3 \"$HERE/claude-pretooluse-secret-guard.py\"" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ['SETTINGS'])
data = json.loads(p.read_text())
hooks = data.get('hooks', {}).get('PreToolUse', [])
command = os.environ['COMMAND']
for entry in list(hooks):
    own = [h for h in entry.get('hooks', []) if h.get('command') == command]
    if not own:
        continue
    entry['hooks'] = [h for h in entry['hooks'] if h.get('command') != command]
    if not entry['hooks']:
        hooks.remove(entry)
    p.write_text(json.dumps(data, indent=2) + '\n')
PY
printf 'secret-guard: own Claude hook removed; Pi extension must be unlinked separately.\n'
