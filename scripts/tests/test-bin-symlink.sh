#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-bin-symlink.sh — `brain` works through the ~/bin symlink setup creates.
#
# setup.sh links ~/bin/brain -> <checkout>/scripts/brain.sh. brain.sh sourced its
# prompt helper relative to BASH_SOURCE without resolving the link, so through
# ~/bin it looked for ~/bin/installer/prompt-helper.sh and every `brain` command
# died on line 16 (2026-09-07). Every script that sources the helper now resolves
# its own real path first.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; ln -s "$ROOT/scripts/brain.sh" "$T/bin/brain"

out="$(bash "$T/bin/brain" --version 2>&1)"; rc=$?
case "$out" in
	*"No such file"*) bad "through-link" "brain via a symlink cannot find its helper: $out" ;;
	*) [ "$rc" -eq 0 ] && ok "through-link" "brain --version works via the bin symlink ($out)" \
		|| bad "through-link" "rc=$rc: $out" ;;
esac

# Every addon whose install.sh links a CLI into a bin dir must work through
# that link too. Discovered from the install scripts and the addon's bin/, so a
# new addon is covered the day it adds a link.
for f in "$ROOT"/system/addons/*/install.sh; do
	grep -qE 'ln -s' "$f" 2>/dev/null || continue
	a="$(basename "$(dirname "$f")")"
	for exe in "$ROOT/system/addons/$a"/bin/*; do
		[ -x "$exe" ] || continue
		ln -sfn "$exe" "$T/bin/$(basename "$exe")"
		out="$("$T/bin/$(basename "$exe")" --help 2>&1 | head -5)"
		case "$out" in
			*"No such file"*|*"not found"*|*Traceback*) bad "addon-$a" "$(basename "$exe") breaks through a bin link: $(printf '%s' "$out" | head -1 | cut -c1-80)" ;;
			*) ok "addon-$a" "$(basename "$exe") works through a bin link" ;;
		esac
	done
done

# Every script that sources the helper relative to itself resolves the link first.
left="$(grep -rn 'prompt-helper.sh' "$ROOT/scripts" --include='*.sh' | grep 'BASH_SOURCE' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -vc 'realpath')"
[ "$left" -eq 0 ] && ok "all-resolve" "every BASH_SOURCE-relative helper source goes through realpath" \
	|| bad "all-resolve" "$left script(s) still source the helper without resolving their own symlink"

[ "$fail" -ne 0 ] && { echo "FAIL test-bin-symlink" >&2; exit 1; }
echo "PASS test-bin-symlink"
