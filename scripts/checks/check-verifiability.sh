#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-verifiability.sh — is every check provably switched on?
#
# The defect this closes: a verification step reporting success while doing
# nothing. A sed that replaces nothing and exits 0. A grep over an error message,
# read as an absence. A find over a symlink that returns zero files while the
# check prints "passed".
#
# Two properties make that class visible, and this reports on both:
#
#   1. A DENOMINATOR. A check that prints how much it examined cannot report a
#      green line after reading nothing, because the green line carries the size
#      of the scan. Counted in the same pass, never by a second command.
#
#   2. A NEGATIVE TEST. A check you have only ever seen pass is a check you do
#      not know is switched on. scripts/checks/negative/<name>.sh sets up a state
#      that must be rejected and asserts the check exits non-zero.
#
# This is a ratchet, not a retrofit. Checks listed in negative/.baseline predate
# the rule and only count towards the coverage figures. Anything newer must ship
# its negative test, so the number goes up and never down.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

# --list prints the checks that still lack a denominator, so the backlog can be
# worked off instead of only watched. Off by default: doctor runs this on every
# invocation and the full list would drown the summary.
LIST=0
for _a in "$@"; do [ "$_a" = "--list" ] && LIST=1; done

NEG_DIR="scripts/checks/negative"
BASELINE="$NEG_DIR/.baseline"
total=0; with_count=0; with_negative=0; missing=""; without_count_names=""

for f in scripts/checks/*.sh; do
	name="$(basename "$f" .sh)"
	case "$name" in doctor|check-verifiability) continue ;; esac
	total=$((total + 1))

	# A denominator: the success line carries a number. A literal "passed" with
	# nothing interpolated cannot tell you whether anything was read.
	#
	# Matched over the success line AND the one after it, because a multi-line
	# printf puts its arguments below the format string:
	#     printf 'check-x: ok (%d addon(s), %d licensed)\n' \
	#         "$checked" "$licensed"
	# and "ok (" counts as much as "ok:" does.
	#
	# A count carries no names to check against, which is why the checks that
	# fail this test are collected by name in $without_count_names below
	# (printed with --list).
	# The success vocabulary is what checks actually print on their last line:
	# passed, ok, all, valid, "no ", OK, healthy, clean. Matching only on
	# "ok|passed" misses lines like `check-events: N event(s) valid`, which
	# carry exactly the number this check is looking for.
	#
	# This stays a heuristic and therefore a LOWER BOUND. Reading the source
	# cannot prove a success line interpolates a count; only running the check
	# and reading its output can, and that is impossible here because doctor
	# runs this check, so it would run every check inside one of them. When the
	# number matters, verify by hand or with --list rather than trusting it.
	if awk '
		# The success line itself must carry the number. Taking the NEXT line
		# unconditionally counted check-english-sources, whose success line is a
		# bare printf with no variable at all and whose neighbour happened to
		# have one. Only a real line continuation ("\\" at the end) reaches over.
		/^[[:space:]]*(echo|printf).*(passed|valid|healthy|clean|ok[ :(]|OK[ :(]|: *all |no [a-z])/ {
			# An array expansion is a list of names, not a count:
			# check-architecture prints ${DOCS[*]} and reads as measured while
			# it reports nothing about size. %d is the only unambiguous signal;
			# a bare $var is a guess that happens to be right more often than not.
			if ($0 ~ /%d/ || ($0 ~ /\$\(|\$[A-Za-z_{]/ && $0 !~ /\[[*@]\]/)) { found = 1 }
			else if ($0 ~ /\\$/)              { cont = NR }
		}
		cont && NR == cont + 1 && /%d|\$\(|\$[A-Za-z_{]/ { found = 1 }
		END { exit found ? 0 : 1 }
	' "$f"; then
		with_count=$((with_count + 1))
	else
		without_count_names="$without_count_names $name"
	fi

	if [ -f "$NEG_DIR/$name.sh" ]; then
		with_negative=$((with_negative + 1))
	elif ! grep -qxF "$name" "$BASELINE" 2>/dev/null; then
		missing="$missing $name"
	fi
done

echo "check-verifiability: $total check(s) examined"
echo "  report a denominator : $with_count"
# Names, not just a count: a number alone gives nothing to read it against.
# --list prints what is missing so it can be worked off.
if [ "${LIST:-0}" = 1 ] && [ -n "$without_count_names" ]; then
	echo "  without a denominator:"
	printf '    %s\n' $without_count_names
fi
echo "  have a negative test : $with_negative"

if [ -n "$missing" ]; then
	echo "" >&2
	for m in $missing; do
		echo "FAIL $m: no $NEG_DIR/$m.sh, and not in the baseline." >&2
	done
	cat >&2 <<'MSG'

   A new check must ship a case that makes it fail. Create the file, set up a
   state the check must reject, and assert a non-zero exit. If this check is
   genuinely untestable, add its name to scripts/checks/negative/.baseline and
   say why in the commit.
MSG
	exit 1
fi
