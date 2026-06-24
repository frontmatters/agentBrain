#!/usr/bin/env bash
# check-doctor.sh — doctor self-check: every scripts/check-*.sh is wired into doctor.sh.
# Catches orphan validators (a check that exists but doctor never runs), so doctor's
# coverage cannot silently rot. doctor checking itself = a real doctor.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DOCTOR="scripts/doctor.sh"

# Advisory checks that intentionally run at deploy/build time, not inside doctor.
# They are non-blocking by design (e.g. exit 3 = advisory), so wiring them into
# doctor's hard run-loop would wrongly fail it. Listed here so the orphan check
# stays green without faking a doctor wiring.
EXEMPT="check-release-published.sh"

errors=0
checked=0
exempted=0
for c in scripts/check-*.sh; do
	[ -f "$c" ] || continue
	name="$(basename "$c")"
	case " $EXEMPT " in *" $name "*) exempted=$((exempted + 1)); continue ;; esac
	checked=$((checked + 1))
	if ! grep -q "$name" "$DOCTOR"; then
		echo "FAIL orphan check: $name exists but is not wired into $DOCTOR" >&2
		errors=$((errors + 1))
	fi
done

if [ "$errors" -gt 0 ]; then
	echo "check-doctor: $errors orphan check(s) — wire them into $DOCTOR" >&2
	exit 1
fi
echo "check-doctor: all $checked check-*.sh wired into doctor ($exempted advisory exempt)"
