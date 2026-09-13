#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-bash32.sh — no bash 4 constructs in code that runs on an install.
#
# macOS ships bash 3.2 as /bin/bash and a fresh Mac runs everything on it.
# `bash -n` on bash 5 cannot see that: `declare -A`, `mapfile`, `readarray`,
# `${x,,}`, `${x^^}`, `${x@Q}`, `|&` and `coproc` parse fine and fail at run
# time. On 2026-09-07 an essential addon's install.sh, addons.sh, report-stale
# and two skill scripts carried them; report-stale went red on every fresh Mac.
# Known false positive: the `|&` arm cannot tell an operator from a character
# class, so a regex containing [|&;] trips it. Order the class as [&|;] instead;
# it matches the same characters and the literal "|&" never appears. Teaching
# this check about bracket expressions costs more fragility than it removes.
#
# Not every arm is a bash 4 construct. `. <(cmd)` parses and runs everywhere,
# and on 3.2 it defines nothing and reports nothing: a sourced file is read with
# seek, and a pipe cannot seek. A characterisation test built that way passed on
# the workstation and reported every row as "nothing" inside the release sandbox,
# which runs on /bin/bash. Write the output to a real file and source that.
#
# Each hit is matched twice: once in the file and once on the "path:line:"
# form the loop reads back, so a leading-context class has to admit ':' as well
# as start-of-line. A new arm that forgets it silently never fires.
#
# Comment lines do not count. A maintainer tool that needs bash 4 says so with
# a BASH_VERSINFO guard and is listed in EXEMPT.
set -uo pipefail
ROOT="$(cd -P "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"
cd "$ROOT" || exit 1
EXEMPT='^(system/references/dev-registry\.scan\.sh|scripts/checks/check-bash32\.sh|scripts/checks/negative/check-bash32\.sh)$'
RE='(^|[^A-Za-z_-])(declare -A|local -A|typeset -A|mapfile|readarray|coproc)([^A-Za-z_-]|$)|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|@[QEPAa])\}|[^|]\|&[^&]|(^|[[:space:]:])(\.|source)[[:space:]]+<\('
fail=0
while IFS= read -r f; do
	[[ "$f" =~ $EXEMPT ]] && continue
	while IFS= read -r line; do
		printf '%s\n' "$line" | grep -qE "$RE" || continue
		echo "  ✗ $line"
		fail=1
	done < <(grep -nE "$RE" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$f:|")
done < <(find scripts system -path '*/node_modules' -prune -o -type f \( -name '*.sh' -o \( -path '*/bin/*' ! -name '*.*' \) \) -print0 2>/dev/null | xargs -0 grep -lE 'bash' 2>/dev/null | sort)
if [ "$fail" -ne 0 ]; then
	echo "check-bash32: constructs that break on macOS /bin/bash 3.2 (see the header of this check)" >&2
	exit 1
fi
echo "check-bash32: ok (no bash 4 constructs outside the exempt maintainer tools)"
