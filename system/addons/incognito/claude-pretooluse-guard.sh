#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# claude-pretooluse-guard.sh — PreToolUse hook for Claude Code.
# When incognito mode is active, BLOCK agent-initiated writes (Write/Edit/MultiEdit)
# to knowledge notes under the vault's local/ tree. PreToolUse runs BEFORE the tool,
# so exit 2 actually prevents the write (PostToolUse would be too late).
#
# Wired in ~/.claude/settings.json under hooks.PreToolUse, matcher "Write|Edit|MultiEdit".
#
# Exit codes (Claude Code contract):
#   0 — allow the tool call (not incognito, or not a vault knowledge write)
#   2 — block: stderr is surfaced to the agent as the reason
#
# Scope: only knowledge under local/ is blocked. Code (system/, scripts/, root)
# and config edits stay allowed — incognito stops NEW KNOWLEDGE, not all work.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Not incognito? allow everything.
bash "$HERE/is-incognito.sh" || exit 0

# Read Claude Code PreToolUse payload from stdin: { tool_name, tool_input:{file_path} }.
FILE_PATH="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    pass
" 2>/dev/null)"

# No file_path → not a file write we care about. Allow.
[ -n "$FILE_PATH" ] || exit 0

# Resolve absolute path (dir may exist even if file doesn't yet for a new Write).
DIR="$(dirname "$FILE_PATH")"
[ -d "$DIR" ] || exit 0
ABS_FILE="$(cd "$DIR" && pwd)/$(basename "$FILE_PATH")"

# Walk up to the brain root (the dir containing brain.json).
BRAIN_ROOT=""
D="$DIR"
while [ "$D" != "/" ]; do
	if [ -f "$D/brain.json" ]; then BRAIN_ROOT="$D"; break; fi
	D="$(dirname "$D")"
done
# Not inside a brain? not our concern. Allow.
[ -n "$BRAIN_ROOT" ] || exit 0

REL="${ABS_FILE#"${BRAIN_ROOT}"/}"

# Only knowledge under local/ is suppressed. Everything else (system/, scripts/,
# root config) stays writable so you can still build/fix during an incognito session.
case "$REL" in
	local/*|vault/*)
		cat >&2 <<EOF
🔒 incognito: write to "$REL" blocked.
agentBrain is read-only this session (raadplegen mag, schrijven niet).
To persist knowledge, turn it off first:  /incognito off
EOF
		exit 2
		;;
esac
exit 0
