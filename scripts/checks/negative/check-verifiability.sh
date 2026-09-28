#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-verifiability.sh: a check with no negative case and no
# baseline entry must be refused. Without this the ratchet could silently accept
# everything, which is the failure it exists to prevent, one level up.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/checks/negative"
cp "$ROOT_DIR/scripts/checks/check-verifiability.sh" "$TMP/scripts/checks/"
printf '#!/usr/bin/env bash\necho ok\n' > "$TMP/scripts/checks/check-unbaselined.sh"
: > "$TMP/scripts/checks/negative/.baseline"
cd "$TMP" || exit 1
if bash scripts/checks/check-verifiability.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: accepted a check with no negative case and no baseline" >&2
	exit 1
fi

# ── the denominator detection must see both easily missed shapes ────────────
# A pattern that requires "ok:" or "passed" with a $ on the same line misses
# two shapes: a success line separating with "(" instead of ":", and a multi-line printf
# whose arguments sit on the next line. Both are fixtures here, because a
# detection nobody has watched find something is a detection nobody knows works.
den() { # <file-body> -> prints the reported denominator count
	local d="$TMP/den"; rm -rf "$d"; mkdir -p "$d/scripts/checks/negative"
	cp "$ROOT_DIR/scripts/checks/check-verifiability.sh" "$d/scripts/checks/"
	printf '%s\n' "$1" > "$d/scripts/checks/check-probe.sh"
	printf 'check-probe\n' > "$d/scripts/checks/negative/.baseline"
	( cd "$d" && bash scripts/checks/check-verifiability.sh 2>/dev/null \
		| awk '/report a denominator/{print $NF}' )
}

fail=0
n="$(den '#!/usr/bin/env bash
printf "check-probe: ok (%d addon(s))\n" "$count"')"
[ "$n" = "1" ] && echo "  ok[paren]: 'ok (' counts as a denominator" \
               || { echo "  FAIL[paren]: 'ok (' was not counted (got $n)" >&2; fail=1; }

n="$(den '#!/usr/bin/env bash
printf "check-probe: ok (%d read, %d skipped)\n" \
	"$read" "$skipped"')"
[ "$n" = "1" ] && echo "  ok[multiline]: a multi-line printf counts" \
               || { echo "  FAIL[multiline]: arguments on the next line were missed (got $n)" >&2; fail=1; }

# And the other direction, or the detection just says yes to everything.
n="$(den '#!/usr/bin/env bash
echo "check-probe: passed"')"
[ "$n" = "0" ] && echo "  ok[literal]: a bare 'passed' is not a denominator" \
               || { echo "  FAIL[literal]: counted a success line with no number (got $n)" >&2; fail=1; }

# A success line whose only variable is an array expansion reports names, not
# a size. check-architecture prints ${DOCS[*]} and read as measured while
# saying nothing about how much it looked at.
n="$(den '#!/usr/bin/env bash
DOCS=(a.md b.md)
echo "check-probe: all paths in ${DOCS[*]} exist"')"
[ "$n" = "0" ] && echo "  ok[array]: an array expansion is not a count" \
               || { echo "  FAIL[array]: counted a list of names as a denominator (got $n)" >&2; fail=1; }

# And the line after a success line only counts when the line actually
# continues. A bare "OK" must not count just because its neighbour happens to
# hold a variable.
n="$(den '#!/usr/bin/env bash
printf "check-probe: OK\n"
some_other_thing="$HOME/x"')"
[ "$n" = "0" ] && echo "  ok[neighbour]: an unrelated next line does not count" \
               || { echo "  FAIL[neighbour]: reached over into the next line without a continuation (got $n)" >&2; fail=1; }

[ "$fail" -eq 0 ] || exit 1
echo "negative/check-verifiability: an unbaselined check without a case is refused"
