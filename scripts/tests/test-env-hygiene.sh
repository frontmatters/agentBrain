#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-env-hygiene.sh: a fixture test holds when the caller says where the brain is.
#
# setup.sh exports VAULT to its children; a shell may export AGENTBRAIN_DIR.
# A test that builds a fixture brain must ignore both, or it checks the real
# checkout and fails only under setup, the installer, or that shell. Measured:
# test-vault-lib red on two machines for five hours, green by hand everywhere.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
cd "$ROOT" || exit 1
for t in test-vault-lib test-check-onboarding test-new-note test-context test-queue; do
	if VAULT=/nonexistent AGENTBRAIN_DIR=/nonexistent bash "scripts/tests/$t.sh" >/dev/null 2>&1; then
		ok "$t" "passes with VAULT and AGENTBRAIN_DIR pointing elsewhere"
	else
		bad "$t" "fails when VAULT or AGENTBRAIN_DIR is set by the caller"
	fi
done
grep -q 'env -u VAULT -u AGENTBRAIN_DIR' scripts/checks/doctor.sh && ok "doctor" "the doctor strips the caller's brain-location variables per check" || bad "doctor" "the doctor passes VAULT/AGENTBRAIN_DIR through to checks"
[ "$fail" -ne 0 ] && { echo "FAIL test-env-hygiene" >&2; exit 1; }
echo "PASS test-env-hygiene"
