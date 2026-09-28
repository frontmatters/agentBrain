#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-exemptions.sh — the exemption register must stay honest.
#
# An expiry date nobody checks is decoration. This validates the shape of every
# row and fails once a dated exemption is past its date, so a temporary
# allowance cannot quietly become permanent.
#
# It also refuses a row with no reason. The reason is the whole point: it is
# what lets the next person decide whether the exemption still earns its place.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
REG="$ROOT_DIR/scripts/lib/exemptions.tsv"
TODAY="$(date +%Y-%m-%d)"

[ -f "$REG" ] || { printf 'check-exemptions: register missing at %s\n' "${REG#"$ROOT_DIR"/}" >&2; exit 1; }

rows=0; bad=0; overdue=0; structural=0; dated=0

while IFS=$'\t' read -r check pattern expires reason; do
	case "${check:-}" in ''|'#'*) continue ;; esac
	rows=$((rows + 1))

	if [ -z "${pattern:-}" ] || [ -z "${expires:-}" ] || [ -z "${reason:-}" ]; then
		printf '  malformed row (needs check, pattern, expires, reason): %s\n' "$check" >&2
		bad=$((bad + 1)); continue
	fi

	# A reason that says nothing is the same as no reason at all.
	if [ "${#reason}" -lt 30 ]; then
		printf '  %s: reason too short to be useful: %s\n' "$check" "$reason" >&2
		bad=$((bad + 1)); continue
	fi

	if [ "$expires" = "structural" ]; then
		structural=$((structural + 1))
		continue
	fi

	if ! printf '%s' "$expires" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
		printf '  %s: expires must be a date or "structural", got: %s\n' "$check" "$expires" >&2
		bad=$((bad + 1)); continue
	fi
	dated=$((dated + 1))
	if [ "$expires" \< "$TODAY" ]; then
		printf '  OVERDUE %s: %s expired on %s\n' "$check" "$pattern" "$expires" >&2
		printf '          %s\n' "$reason" >&2
		overdue=$((overdue + 1))
	fi
done < "$REG"

# A register that parsed to nothing looks exactly like a register with no
# problems. Say the denominator.
if [ "$rows" -eq 0 ]; then
	printf 'check-exemptions: no rows parsed — is the register tab separated?\n' >&2
	exit 1
fi

if [ "$bad" -gt 0 ] || [ "$overdue" -gt 0 ]; then
	printf 'check-exemptions: %d row(s), %d malformed, %d overdue\n' "$rows" "$bad" "$overdue"
	exit 1
fi
printf 'check-exemptions: %d exemption(s) — %d structural, %d dated, 0 overdue\n' "$rows" "$structural" "$dated"
