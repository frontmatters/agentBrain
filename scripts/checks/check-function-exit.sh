#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-function-exit.sh — a function must not end on a bare && chain.
#
# Under `set -e` a function returns the status of its last command. End a taken
# branch on `cmd && echo ...` and a failing `cmd` makes the whole function fail,
# so `x="$(f)"` aborts the caller with no message, at a line that looks innocent.
# The failure hides well: every assertion before it prints ok, the summary line
# never runs, and the exit code says 1 while the output says fine.
#
# Only `&&` chains and bare tests are flagged. `if` and `case` are NOT: bash
# gives both exit 0 when no branch is taken, measured:
#   if false; then echo x; fi        -> 0
#   case zzz in aaa) echo x ;; esac  -> 0
#   false && echo x                  -> 1
#   if true; then false && echo x; fi-> 1
# Flagging `esac` and `fi` would be a false positive on a function whose arms
# all end on a plain echo.
#
# Example: `command -v brew >/dev/null 2>&1 && echo "brew install x"` as the last
# line of a case arm kills every caller under set -e on a host without brew.
# This class is not reported by shellcheck, even at -S style. Hence this check.
# (Do not start that sentence with the tool name: a comment opening with the
#  word shellcheck is parsed as a directive, which fails with SC1073.)
#
# A chain counts as an ending when the next effective line closes its block:
# `;;`, `fi`, `esac`, `else`, `elif`, `done`, or the function's own brace.
# Add `|| true`, or `|| return 0`, to say the empty case is fine.
#
# WARN-first by design, like check-decisions: an existing tree with hits must not
# break doctor on day one. Promote to FAIL once the count reaches zero.
set -uo pipefail
ROOT="$(cd -P "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"
cd "$ROOT" || exit 1

EXEMPT='^(scripts/checks/check-function-exit\.sh|scripts/checks/negative/check-function-exit\.sh)$'
RATCHET="scripts/checks/.function-exit-ratchet.json"

# Default output is the count only; doctor runs this on every push and a line
# per hit is noise nobody reads. `--list` prints the branches themselves.
LIST=false
[ "${1:-}" = "--list" ] && LIST=true

hits=0
while IFS= read -r f; do
	[ -f "$f" ] || continue          # a path staged for deletion is still listed
	[[ "$f" =~ $EXEMPT ]] && continue
	out="$(awk -v F="$f" '
	function eff(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
	# Collect the function body with line numbers, then look for && chains whose
	# next effective line closes the block they sit in.
	function scan(   i, j, l, nxt) {
		if (fname == "") return
		for (i = 1; i <= n; i++) {
			l = eff(body[i])
			if (l == "" || l ~ /^#/) continue
			if (l !~ /&&/ || l ~ /\|\|/) continue
			nxt = ""
			for (j = i + 1; j <= n; j++) {
				nxt = eff(body[j])
				if (nxt != "" && nxt !~ /^#/) break
				nxt = ""
			}
			if (nxt == "" || nxt ~ /^(;;|fi|esac|else|elif|done)([ \t;].*)?$/)
				printf "WARN %s:%d %s(): && chain with no || fallback ends a branch\n", F, lineno[i], fname
		}
		fname = ""; n = 0
	}
	/^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{[ \t]*$/ {
		scan(); fname = $0; sub(/\(\).*/, "", fname); n = 0; next
	}
	/^\}[ \t]*$/ { scan(); next }
	fname != "" { n++; body[n] = $0; lineno[n] = NR }
	END { scan() }
	' "$f")"
	if [ -n "$out" ]; then
		[ "$LIST" = true ] && printf '%s\n' "$out"
		hits=$((hits + $(printf '%s\n' "$out" | grep -c '^WARN ')))
	fi
done < <(git ls-files '*.sh' 2>/dev/null)

ceiling="$(sed -n 's/.*"unguarded" *: *\([0-9]*\).*/\1/p' "$RATCHET" 2>/dev/null || true)"
ceiling="${ceiling:-$hits}"

if [ "$hits" -gt "$ceiling" ]; then
	printf 'FAIL branches ending on a bare && chain: %d -> %d (may only fall).\n' "$ceiling" "$hits" >&2
	printf '  -> append `|| true` (or `|| return 0`) to the new one, or lower the ratchet.\n' >&2
	printf '  -> run with --list to see which branches.\n' >&2
	exit 1
fi
if [ "$hits" -lt "$ceiling" ]; then
	printf 'check-function-exit: ok (%d, below the ceiling of %d — lower %s)\n' "$hits" "$ceiling" "$RATCHET"
	exit 0
fi
printf 'check-function-exit: ok (%d unguarded, ceiling %d)\n' "$hits" "$ceiling"
