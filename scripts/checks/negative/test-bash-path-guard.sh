#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for the bash path guard: it must block a read command on a relative path
# that does not exist here, and it must NOT block a pattern that merely contains slashes.
# The second half is what keeps the guard usable — a guard that cries wolf gets turned off.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOK="$ROOT_DIR/scripts/claude-bash-path-guard.py"

payload() { python3 -c "import json,sys;print(json.dumps({'tool_name':'Bash','cwd':sys.argv[1],'tool_input':{'command':sys.argv[2]}}))" "$1" "$2"; }

if payload "$ROOT_DIR" 'cat er/is/geen/bestand.md' | python3 "$HOOK" >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: the guard allowed a read on a path that does not exist here" >&2; exit 1
fi
if ! payload "$ROOT_DIR" 'grep -rn "a/b/c" vault/' | python3 "$HOOK" >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: the guard blocked a pattern containing slashes" >&2; exit 1
fi
echo "negative case holds: the guard blocks a missing relative path, not a slashed pattern"
