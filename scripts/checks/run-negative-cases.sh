#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# run-negative-cases.sh — run every negative case and require each to hold.
#
# check-verifiability.sh asks whether a negative case EXISTS. This one asks
# whether it still passes. A negative case that has quietly stopped rejecting is
# the same failure it was written to prevent, one level up.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

ran=0; failed=0
for t in scripts/checks/negative/*.sh; do
	[ -f "$t" ] || continue
	ran=$((ran + 1))
	if ! out="$(bash "$t" 2>&1)"; then
		echo "FAIL $t" >&2
		printf '%s\n' "$out" | sed 's/^/    /' >&2
		failed=$((failed + 1))
	fi
done

if [ "$ran" -eq 0 ]; then
	echo "run-negative-cases: no cases found in scripts/checks/negative/"
	exit 0
fi
[ "$failed" -eq 0 ] || { echo "run-negative-cases: $failed of $ran case(s) failed" >&2; exit 1; }
echo "run-negative-cases: $ran case(s) still reject what they should"
