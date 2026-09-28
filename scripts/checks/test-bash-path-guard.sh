#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-bash-path-guard.sh — cases for scripts/claude-bash-path-guard.py.
#
# A guard without tests rots: the negative cases are what keep it from crying wolf, and a
# hook that cries wolf gets switched off. The pattern-with-a-slash case below is the one
# that matters most — `grep "packages/client" .` must NEVER be blocked.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
HOOK="$ROOT_DIR/scripts/claude-bash-path-guard.py"
errors=0

check_case() { # check_case <expected exit> <cwd> <command> <description>
	local expected="$1" cwd="$2" cmd="$3" desc="$4" code
	python3 -c "import json,sys;print(json.dumps({'tool_name':'Bash','cwd':sys.argv[1],'tool_input':{'command':sys.argv[2]}}))" \
		"$cwd" "$cmd" | python3 "$HOOK" >/dev/null 2>&1 && code=0 || code=$?
	if [ "$code" = "$expected" ]; then
		printf '  ok   %s\n' "$desc"
	else
		printf '  FAIL %s (exit %s, expected %s)\n' "$desc" "$code" "$expected" >&2
		errors=$((errors + 1))
	fi
}

B="$ROOT_DIR"

echo "must block:"
check_case 2 "$B" 'grep -nE "something" packages/client/src/app.ts' "read command on a path from another repo"
check_case 2 "$B" 'sed -n "1,20p" docs/manual/shell.css' "sed on a path from another repo"
check_case 2 "$B" 'cat docs/ARCHITECTURE.md' "cat on a path from another repo"

echo "must pass:"
check_case 0 "$B" 'grep -rn "packages/client/src" vault/' "a PATTERN containing slashes"
check_case 0 "$B" 'rg "a/b/c" vault/learnings' "an rg pattern containing slashes"
check_case 0 "$B" 'grep -rn "something" vault/*/learnings' "a glob"
check_case 0 "$B" 'ls -la vault/learnings' "an existing relative path"
# The cd is honoured: this path does not exist from $B, but it does from the target.
ELSEWHERE="$(mktemp -d)"; trap 'rm -rf "$ELSEWHERE"' EXIT
mkdir -p "$ELSEWHERE/pkg/src"; : > "$ELSEWHERE/pkg/src/file.ts"
check_case 0 "$B" "cd $ELSEWHERE && cat pkg/src/file.ts" "a cd makes the call self-contained"
check_case 2 "$B" "cat pkg/src/file.ts" "the same path without the cd"
check_case 0 "$B" 'echo hello > logs/out.txt' "a redirect, not a read command"
check_case 0 "$B" 'curl -s https://example.com/a/b' "a URL"
check_case 0 "$B" 'grep -n foo "$HOME/x/y.txt"' "a variable inside the path"
check_case 0 "$B" 'git add packages/client/src' "not a read command"
# Found the hard way, minutes after installing the guard: shlex keeps `>/dev/null` as one
# token, it contains a slash, and nothing existed at that "path".
check_case 0 "$B" 'ls CHANGELOG.md >/dev/null 2>&1' "a redirect target is not an argument"
check_case 0 "$B" 'cat README.md > /tmp/x.txt' "a spaced redirect target"
check_case 0 "$B" 'wc -l vault/learnings/patterns.md 2>/dev/null' "a numbered redirect"

if [ "$errors" -gt 0 ]; then
	echo "test-bash-path-guard: $errors failure(s)." >&2
	exit 1
fi
echo "test-bash-path-guard: ok"
