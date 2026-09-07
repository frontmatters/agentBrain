#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# claude-code-validate-note-id-hook.sh — PostToolUse hook for Claude Code.
# Detects Write/Edit tool-use against brain notes and runs the moment-of-write
# checks. Layer 1 of the agent-discipline enforcement framework: catches at the
# moment of writing what would otherwise only surface at the next loop-tick.
#
# Two checks run here, and the name of this file has stayed put because it is
# spelled out in every existing ~/.claude/settings.json:
#   validate-note-id  id-field mistakes (made-up UUIDs, copy-paste errors)
#   check-intake      invisible characters carried in from outside
#
# Wired in ~/.claude/settings.json under hooks.PostToolUse, matcher "Write|Edit".
#
# Claude Code passes tool-call JSON on stdin. We extract file_path, call the
# language-agnostic validator (scripts/hooks/validate-note-id.sh), and exit:
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

# Invisible characters, but only inside the brain. This hook sees every Write
# the agent makes anywhere on the machine, and a test fixture is allowed to
# contain a bidi override — a note is not.
BRAIN="${BRAIN_ALIAS:-$HOME/agentBrain}"
case "$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && pwd -P)/" in
"$(cd -P "$BRAIN" 2>/dev/null && pwd -P)"/* | "$(cd -P "$BRAIN/vault" 2>/dev/null && pwd -P)"/*)
	# No exemption for test fixtures. A test that needs one of these characters
	# writes it as an escape, which is how test-intake.sh does it; the moment
	# tests are exempt here but not at the commit boundary, the two layers
	# disagree about what the rule is.
	#
	# Run it once and hold the report: calling it a second time to print would
	# abort the hook under `set -e` before it could exit 2.
	if ! intake_out="$(bash "$SCRIPT_DIR/checks/check-intake.sh" "$FILE_PATH" 2>&1)"; then
		printf '%s\n' "$intake_out" >&2
		exit 2
	fi
	;;
esac
exit 0
