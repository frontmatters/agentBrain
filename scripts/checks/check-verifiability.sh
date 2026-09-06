#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-verifiability.sh — is every check provably switched on?
#
# On 2026-09-06 the same defect appeared twelve times in one day: a verification
# step reporting success while doing nothing. A sed that replaced nothing and
# exited 0. A grep over an error message, read as an absence. A find over a
# symlink that returned zero files while the check printed "passed".
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

NEG_DIR="scripts/checks/negative"
BASELINE="$NEG_DIR/.baseline"
total=0; with_count=0; with_negative=0; missing=""

for f in scripts/checks/*.sh; do
	name="$(basename "$f" .sh)"
	case "$name" in doctor|check-verifiability) continue ;; esac
	total=$((total + 1))

	# A denominator: the success line interpolates something. A literal "passed"
	# with no variable in it cannot tell you whether anything was read.
	if grep -qE '^[[:space:]]*(echo|printf).*(passed|ok:|OK:).*\$' "$f"; then
		with_count=$((with_count + 1))
	fi

	if [ -f "$NEG_DIR/$name.sh" ]; then
		with_negative=$((with_negative + 1))
	elif ! grep -qxF "$name" "$BASELINE" 2>/dev/null; then
		missing="$missing $name"
	fi
done

echo "check-verifiability: $total check(s) examined"
echo "  report a denominator : $with_count"
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
