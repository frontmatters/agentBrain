#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
COMMAND="python3 \"$HERE/claude-pretooluse-secret-guard.py\""
# Registration is explicit: this script is only run on the owner's request.
mkdir -p "$(dirname "$SETTINGS")"
COMMAND="$COMMAND" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ['SETTINGS'])
data = json.loads(p.read_text()) if p.exists() else {}
hooks = data.setdefault('hooks', {}).setdefault('PreToolUse', [])
command = os.environ['COMMAND']
if not any(h.get('matcher') == '*' and any(x.get('command') == command for x in h.get('hooks', [])) for h in hooks):
    hooks.append({'matcher': '*', 'hooks': [{'type': 'command', 'command': command}]})
    p.write_text(json.dumps(data, indent=2) + '\n')
PY
printf 'secret-guard: Claude PreToolUse registered in %s\n' "$SETTINGS"
printf 'Pi: link system/pi-config/extensions/secret-guard.ts into the Pi extensions directory via your normal Pi setup.\n'
