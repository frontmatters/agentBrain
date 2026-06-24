#!/usr/bin/env bash
# claude-code-validate-note-id-hook.sh — PostToolUse hook for Claude Code.
# Detects Write/Edit tool-use against brain notes and runs validate-note-id.sh.
# Layer 1 of the agent-discipline enforcement framework: catches id-field
# mistakes (made-up UUIDs, copy-paste errors) at moment-of-write, not at
# next loop-tick.
#
# Wired in ~/.claude/settings.json under hooks.PostToolUse, matcher "Write|Edit".
#
# Claude Code passes tool-call JSON on stdin. We extract file_path, call the
# language-agnostic validator (scripts/validate-note-id.sh), and exit:
#   0 — validation passed or not applicable (non-note, non-local, no id field)
#   2 — validation failed: agent sees stderr as system reminder + retries

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read tool-call JSON from stdin (Claude Code hook payload).
# Defensive: if payload malformed, silent no-op rather than blocking unrelated tool calls.
FILE_PATH="$(python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    # Claude Code PostToolUse payload shape: { tool_name, tool_input: { file_path, ... } }
    ti = d.get('tool_input', {})
    print(ti.get('file_path', ''))
except Exception:
    pass
" 2>/dev/null)"

# No file_path? not a Write/Edit on a file — no-op.
[ -n "$FILE_PATH" ] || exit 0

# Run the validator; if it fails, propagate exit code 2 so Claude Code surfaces it.
if ! bash "$SCRIPT_DIR/validate-note-id.sh" "$FILE_PATH"; then
	exit 2
fi
exit 0
