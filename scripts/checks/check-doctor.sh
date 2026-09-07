#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-doctor.sh — doctor self-check: every scripts/check-*.sh is wired into doctor.sh.
# Catches orphan validators (a check that exists but doctor never runs), so doctor's
# coverage cannot silently rot. doctor checking itself = a real doctor.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR"

DOCTOR="scripts/checks/doctor.sh"

# Advisory checks that intentionally run outside doctor. Either they run at
# deploy/build time (e.g. check-release-published.sh, exit 3 = advisory), or they
# inspect per-machine private infrastructure that must never fail another machine's
# shared doctor (check-cmdb-coverage.sh — always exit 0, local-only). Wiring these
# into doctor's hard run-loop would wrongly fail it. Listed here so the orphan
# check stays green without faking a doctor wiring.
EXEMPT="check-cmdb-coverage.sh check-work-note-structure.sh"   # check-release-published moved to the factory (tools/checks/)
# Tests too: a test that is not wired runs nowhere. Measured once: 18 of 57
# tests, six of them red for weeks, none of them in the doctor.
# test-addons-release aggregates the addon suites check-skill-tests already
# runs, plus coverage; it is the release gate's, not the doctor's.
# test-doctor.sh starts a doctor of its own; inside the doctor it waits on the
# lock its parent holds, and the whole run hangs to the 15-minute timeout
# (measured: a pre-push that reported nothing and a push that failed blind).
TEST_EXEMPT="test-addons-release.sh test-doctor.sh"
# check-work-note-structure.sh: work-note-contract ratchet, PRE-CUTOVER — 64
# blocking MUST-debts still in the vault. Runs standalone (and in preflight)
# until scripts/retrofit-work-notes.sh clears the debt per note; then wire it
# into doctor.sh and drop it from this list.

errors=0
checked=0
exempted=0
for c in scripts/check-*.sh; do
	[ -f "$c" ] || continue
	# A shim on an OLD name (its target has another basename) is not a check of its
	# own; the regular scripts/check-x.sh -> checks/check-x.sh shim still counts.
	if [ -L "$c" ] && [ "$(basename "$(realpath "$c")")" != "$(basename "$c")" ]; then continue; fi
	name="$(basename "$c")"
	case " $EXEMPT " in *" $name "*) exempted=$((exempted + 1)); continue ;; esac
	checked=$((checked + 1))
	if ! grep -q "$name" "$DOCTOR"; then
		echo "FAIL orphan check: $name exists but is not wired into $DOCTOR" >&2
		errors=$((errors + 1))
	fi
done

tests_checked=0
for c in scripts/tests/test-*.sh; do
	[ -f "$c" ] || continue
	# A shim on an OLD name (its target has another basename) is not a check of its
	# own; the regular scripts/check-x.sh -> checks/check-x.sh shim still counts.
	if [ -L "$c" ] && [ "$(basename "$(realpath "$c")")" != "$(basename "$c")" ]; then continue; fi
	name="$(basename "$c")"
	case " $TEST_EXEMPT " in *" $name "*) exempted=$((exempted + 1)); continue ;; esac
	tests_checked=$((tests_checked + 1))
	if ! grep -q "$name" "$DOCTOR"; then
		echo "FAIL orphan test: $name exists but is not wired into $DOCTOR" >&2
		errors=$((errors + 1))
	fi
done

if [ "$errors" -gt 0 ]; then
	echo "check-doctor: $errors orphan check(s) — wire them into $DOCTOR" >&2
	exit 1
fi
echo "check-doctor: all $checked check-*.sh and $tests_checked test-*.sh wired into doctor ($exempted exempt)"
