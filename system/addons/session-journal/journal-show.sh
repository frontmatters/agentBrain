#!/usr/bin/env bash
# Pretty-print the current session journal.
# Usage: journal-show.sh [--lines N]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
JOURNAL="$BRAIN_ROOT/local/sessions/session-journal.md"
LOCAL_CONFIG="$BRAIN_ROOT/local/sessions/journal-config.json"
DEFAULT_CONFIG="$HERE/config.default.json"

config_path="$DEFAULT_CONFIG"
[[ -f "$LOCAL_CONFIG" ]] && config_path="$LOCAL_CONFIG"

lines=$(python3 -c "
import json
try:
    c = json.load(open('$config_path'))
    print(c.get('slash_command',{}).get('show_lines',60))
except Exception:
    print(60)
" 2>/dev/null || echo 60)

while [[ $# -gt 0 ]]; do
	case "$1" in
		--lines) lines="$2"; shift 2 ;;
		*) shift ;;
	esac
done

if [[ ! -f "$JOURNAL" ]]; then
	echo "No session-journal.md yet at: $JOURNAL"
	exit 0
fi

echo "── session-journal.md ($(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$JOURNAL" 2>/dev/null || stat -c '%y' "$JOURNAL")) ──"
head -n "$lines" "$JOURNAL"
