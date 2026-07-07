#!/usr/bin/env bash
# Claude Code PostToolUse hook adapter — periodic autosave during long sessions.
# Reads {tool_name, tool_input, transcript_path, ...} JSON on stdin.
# Throttles via mtime of the journal file (no lockfile, no race conditions).
# Always exits 0.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Incognito: read-only session → skip journaling entirely.
[ -f "$HERE/../incognito/is-incognito.sh" ] && bash "$HERE/../incognito/is-incognito.sh" && exit 0
BRAIN_ROOT="$(cd "$HERE/../../.." && pwd)"
JOURNAL="$BRAIN_ROOT/local/sessions/session-journal.md"
LOCAL_CONFIG="$BRAIN_ROOT/local/sessions/journal-config.json"
DEFAULT_CONFIG="$HERE/config.default.json"

config_path="$DEFAULT_CONFIG"
[[ -f "$LOCAL_CONFIG" ]] && config_path="$LOCAL_CONFIG"

payload="$(cat || true)"
[[ -z "$payload" ]] && exit 0

# Resolve config: mode, throttle, matcher.
read -r mode throttle matcher <<<"$(python3 -c "
import json
try:
    c = json.load(open('$config_path'))
except Exception:
    print('throttled_tool_use 300 Write|Edit|MultiEdit'); raise SystemExit
a = c.get('autosave',{})
print(a.get('mode','throttled_tool_use'), a.get('throttle_seconds',300), a.get('matcher','Write|Edit|MultiEdit'))
" 2>/dev/null || echo "throttled_tool_use 300 Write|Edit|MultiEdit")"

[[ "$mode" == "disabled" ]] && exit 0
# In interval mode the autosave is launchd-driven, not hook-driven.
[[ "$mode" == "interval" ]] && exit 0

# Pull tool_name and transcript_path from the payload.
read -r tool_name transcript_path <<<"$(printf '%s' "$payload" | python3 -c "
import json,sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('tool_name',''), d.get('transcript_path',''))
except Exception:
    print('','')
" 2>/dev/null || echo " ")"

# Matcher: skip if tool isn't in scope. The hook matcher already filters but be defensive.
if ! [[ "$tool_name" =~ ^($matcher)$ ]]; then
	exit 0
fi

# Throttle via mtime.
if [[ -f "$JOURNAL" ]]; then
	now=$(date +%s)
	mtime=$(stat -f %m "$JOURNAL" 2>/dev/null || stat -c %Y "$JOURNAL" 2>/dev/null || echo 0)
	delta=$(( now - mtime ))
	if (( delta < throttle )); then
		exit 0
	fi
fi

[[ -z "$transcript_path" ]] && exit 0

# Run detached, silent, non-blocking.
(
	printf '%s' "$payload" | bash "$HERE/journal-update.sh" --stdin --source autosave
) >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
