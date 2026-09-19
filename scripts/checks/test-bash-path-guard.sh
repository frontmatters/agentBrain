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
fouten=0

toets() { # toets <verwachte exit> <cwd> <commando> <omschrijving>
	local verwacht="$1" cwd="$2" cmd="$3" wat="$4" code
	python3 -c "import json,sys;print(json.dumps({'tool_name':'Bash','cwd':sys.argv[1],'tool_input':{'command':sys.argv[2]}}))" \
		"$cwd" "$cmd" | python3 "$HOOK" >/dev/null 2>&1 && code=0 || code=$?
	if [ "$code" = "$verwacht" ]; then
		printf '  ok   %s\n' "$wat"
	else
		printf '  FAIL %s (exit %s, expected %s)\n' "$wat" "$code" "$verwacht" >&2
		fouten=$((fouten + 1))
	fi
}

B="$ROOT_DIR"

echo "must block:"
toets 2 "$B" 'grep -nE "iets" packages/client/src/app.ts' "read command on a path from another repo"
toets 2 "$B" 'sed -n "1,20p" docs/handleiding/shell.css' "sed on a path from another repo"
toets 2 "$B" 'cat docs/ARCHITECTURE.md' "cat on a path from another repo"

echo "must pass:"
toets 0 "$B" 'grep -rn "packages/client/src" vault/' "a PATTERN containing slashes"
toets 0 "$B" 'rg "a/b/c" vault/learnings' "an rg pattern containing slashes"
toets 0 "$B" 'grep -rn "iets" vault/*/learnings' "a glob"
toets 0 "$B" 'ls -la vault/learnings' "an existing relative path"
# The cd is honoured: this path does not exist from $B, but it does from the target.
ELDERS="$(mktemp -d)"; trap 'rm -rf "$ELDERS"' EXIT
mkdir -p "$ELDERS/pakket/bron"; : > "$ELDERS/pakket/bron/bestand.ts"
toets 0 "$B" "cd $ELDERS && cat pakket/bron/bestand.ts" "a cd makes the call self-contained"
toets 2 "$B" "cat pakket/bron/bestand.ts" "the same path without the cd"
toets 0 "$B" 'echo hallo > logs/uit.txt' "a redirect, not a read command"
toets 0 "$B" 'curl -s https://example.com/a/b' "a URL"
toets 0 "$B" 'grep -n foo "$HOME/x/y.txt"' "a variable inside the path"
toets 0 "$B" 'git add packages/client/src' "not a read command"
# Found the hard way, minutes after installing the guard: shlex keeps `>/dev/null` as one
# token, it contains a slash, and nothing existed at that "path".
toets 0 "$B" 'ls CHANGELOG.md >/dev/null 2>&1' "a redirect target is not an argument"
toets 0 "$B" 'cat README.md > /tmp/x.txt' "a spaced redirect target"
toets 0 "$B" 'wc -l vault/learnings/patterns.md 2>/dev/null' "a numbered redirect"

if [ "$fouten" -gt 0 ]; then
	echo "test-bash-path-guard: $fouten failure(s)." >&2
	exit 1
fi
echo "test-bash-path-guard: ok"
