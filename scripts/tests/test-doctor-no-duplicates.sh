#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-doctor-no-duplicates.sh — the doctor must run each check once.
#
# check-skill-tests was listed twice, so every test a skill ships with ran twice
# in every doctor: minutes of duplicated work, and on 2026-09-13 a release gate
# that refused because the first invocation passed and the second did not. A
# check that gives two answers in one run is a defect on its own; a list that
# asks for two answers hides it.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
DOCTOR="$ROOT_DIR/scripts/checks/doctor.sh"

# The entries are quoted command strings in the arrays doctor iterates over.
# Compared on the command, not the whole line: a trailing comment differed
# between the two copies, which is exactly how a duplicate stays invisible.
dupes="$(grep -oE '^[[:space:]]*"bash [^"]+"' "$DOCTOR" \
	| sed 's/^[[:space:]]*//' \
	| sort | uniq -d)"

if [ -n "$dupes" ]; then
	printf 'test-doctor-no-duplicates: listed more than once in doctor.sh:\n' >&2
	printf '  %s\n' "$dupes" >&2
	exit 1
fi

n="$(grep -cE '^[[:space:]]*"bash [^"]+"' "$DOCTOR")"
if [ "$n" -lt 50 ]; then
	printf 'test-doctor-no-duplicates: only %s entries matched — has the list changed shape?\n' "$n" >&2
	exit 1
fi
printf 'test-doctor-no-duplicates: %s entries, none listed twice\n' "$n"
