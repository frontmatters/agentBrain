#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-exemptions.sh: a register that has gone soft is
# rejected. An expiry nobody enforces is decoration, and a reason that says
# nothing is the same as no reason, so both must actually fail the check.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECK="$ROOT_DIR/scripts/checks/check-exemptions.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/checks" "$TMP/scripts/lib"
cp "$CHECK" "$TMP/scripts/checks/"
REG="$TMP/scripts/lib/exemptions.tsv"

good() { printf 'em-dash\tsome-pattern\tstructural\tA reason long enough to actually tell the next reader why this exists.\n' > "$REG"; }

# 1. A well-formed register passes, so the failures below mean something.
good
if ! bash "$TMP/scripts/checks/check-exemptions.sh" >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-exemptions rejected a well-formed register" >&2; exit 1
fi

# 2. A dated row that is past its date must fail. This is the whole point: a
#    temporary allowance must not be able to become permanent by being ignored.
good
printf 'em-dash\tstale\t2020-01-01\tThis row expired years ago and the check must say so instead of passing.\n' >> "$REG"
if bash "$TMP/scripts/checks/check-exemptions.sh" >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-exemptions passed an exemption that expired in 2020" >&2; exit 1
fi

# 3. A row with no reason must fail.
good
printf 'em-dash\tnoreason\tstructural\t\n' >> "$REG"
if bash "$TMP/scripts/checks/check-exemptions.sh" >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-exemptions passed a row with no reason" >&2; exit 1
fi

# 4. A reason too short to help anyone must fail. "legacy" is not a reason.
good
printf 'em-dash\tterse\tstructural\tlegacy\n' >> "$REG"
if bash "$TMP/scripts/checks/check-exemptions.sh" >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-exemptions passed a one-word reason" >&2; exit 1
fi

# 5. An expiry that is not a date and not "structural" must fail, so nobody can
#    write "soon" or "never" and slip past the date arithmetic.
good
printf 'em-dash\tvague\tnever\tA row trying to claim it never expires without saying it is structural.\n' >> "$REG"
if bash "$TMP/scripts/checks/check-exemptions.sh" >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-exemptions accepted an expiry of 'never'" >&2; exit 1
fi

# 6. An empty register must fail rather than report a clean bill: no rows
#    parsed looks exactly like no problems found.
: > "$REG"
if bash "$TMP/scripts/checks/check-exemptions.sh" >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-exemptions passed on an empty register" >&2; exit 1
fi

echo "negative case holds: check-exemptions rejects expired rows, missing reasons and vague expiries"
