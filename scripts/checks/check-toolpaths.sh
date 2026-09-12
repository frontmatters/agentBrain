#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-toolpaths.sh — probe a user-scoped tool only after loading its paths.
#
# scripts/lib/_toolpaths.sh has stated the rule in its header from the start:
# "every script that probes tools sources this first, so we never claim 'not
# installed' for something that is." Nothing enforced it, and the gap is not
# cosmetic. shorthand's installer probed `bun` without loading the paths while
# check-shorthand probed with them: the install skipped its own setup step, the
# check ran anyway, and every fresh machine failed the doctor on drift the
# install had been prevented from avoiding.
#
# bun, node, npm, uv and deno live in user-scoped installs (nvm, ~/.bun,
# ~/.local/bin, Homebrew) that a restricted PATH does not carry. A login shell
# has them; a launchd job, a sandbox, an installer sub-shell and a git hook do
# not.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

TOOLS='bun|node|npm|npx|uv|deno'
REG="$ROOT_DIR/scripts/lib/exemptions.tsv"

exempt() { # exempt <path>
	[ -f "$REG" ] || return 1
	local check pattern _expires _reason
	while IFS=$'\t' read -r check pattern _expires _reason; do
		[ "${check:-}" = "toolpaths" ] || continue
		[ -n "${pattern:-}" ] || continue
		# The register holds globs, so the expansion is meant to glob here.
		# shellcheck disable=SC2254
		case "$1" in $pattern) return 0 ;; esac
	done < "$REG"
	return 1
}

checked=0; bad=0; exempted=0
while IFS= read -r f; do
	[ -f "$f" ] || continue
	# The loader itself, and anything exempted with a reason on record.
	case "$f" in */lib/_toolpaths.sh) continue ;; esac
	grep -qE "command -v[[:space:]]+($TOOLS)\b" "$f" || continue
	# Count BEFORE exempting. Skipping first made an exempted file invisible to
	# the denominator, so exempting the only probing script left the sweep
	# looking like it had nothing to examine, which the guard below calls an
	# error rather than a pass.
	checked=$((checked + 1))
	exempt "$f" && { exempted=$((exempted + 1)); continue; }
	grep -q '_toolpaths' "$f" && continue
	printf '  %s probes a user-scoped tool without loading scripts/lib/_toolpaths.sh\n' "$f" >&2
	bad=$((bad + 1))
done < <(find scripts system -name '*.sh' -type f 2>/dev/null | sort)

# A sweep that examined nothing reads exactly like a clean one.
if [ "$checked" -eq 0 ]; then
	printf 'check-toolpaths: no script probes a user-scoped tool — has the tool list moved?\n' >&2
	exit 1
fi

if [ "$bad" -gt 0 ]; then
	printf 'check-toolpaths: %d of %d probing script(s) skip the loader.\n' "$bad" "$checked"
	printf '  Add near the top, or register an exemption with a reason:\n'
	printf '    _ab_tp="$(cd "$(dirname "${BASH_SOURCE[0]}")/<up>" && pwd)/scripts/lib/_toolpaths.sh"\n'
	printf '    [ -f "$_ab_tp" ] && . "$_ab_tp"\n'
	exit 1
fi
printf 'check-toolpaths: %d probing script(s) load the tool paths first (%d exempted)\n' "$((checked - exempted))" "$exempted"
