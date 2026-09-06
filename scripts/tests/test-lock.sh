#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-lock.sh — two runs that share the vault's fixtures do not overlap.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0
ok() { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
LOCKDIR="$(mktemp -d)"; trap 'rm -rf "$LOCKDIR"' EXIT

# Holder keeps the lock 2s; a second acquirer must wait, then get it.
( TMPDIR="$LOCKDIR"; . "$ROOT/scripts/lib/lock.sh"; acquire_lock t 10; sleep 2 ) &
sleep 0.3
t0=$(date +%s)
( TMPDIR="$LOCKDIR"; . "$ROOT/scripts/lib/lock.sh"; acquire_lock t 10 2>/dev/null ) && waited=$(( $(date +%s) - t0 )) || waited=-1
wait
[ "$waited" -ge 1 ] && ok "waits" "second run waited ${waited}s for the first" || bad "waits" "second run did not wait (${waited}s)"

# The lock is released on exit: a third run gets it at once.
t0=$(date +%s); ( TMPDIR="$LOCKDIR"; . "$ROOT/scripts/lib/lock.sh"; acquire_lock t 10 2>/dev/null ) && [ $(( $(date +%s) - t0 )) -le 1 ] && ok "released" "released on exit" || bad "released" "lock survived its holder"

# A stale lock (crashed holder) is stolen, not honoured.
mkdir "$LOCKDIR/agentbrain-s.lock"; touch -t 202001010000 "$LOCKDIR/agentbrain-s.lock"
t0=$(date +%s); ( TMPDIR="$LOCKDIR"; . "$ROOT/scripts/lib/lock.sh"; acquire_lock s 10 300 2>/dev/null ) && [ $(( $(date +%s) - t0 )) -le 2 ] && ok "stale" "a stale lock is stolen" || bad "stale" "a stale lock blocked the run"

# A child of the holder must not wait on its parent: doctor runs tests that
# run doctor.
t0=$(date +%s)
( TMPDIR="$LOCKDIR"; export TMPDIR; . "$ROOT/scripts/lib/lock.sh"; acquire_lock r 10; bash -c ". '$ROOT/scripts/lib/lock.sh'; acquire_lock r 10" ) 2>/dev/null
[ $(( $(date +%s) - t0 )) -le 1 ] && ok "reentrant" "a nested run under the holder proceeds at once" || bad "reentrant" "a nested run waited on its own ancestor"

# doctor and the pre-push hook use it.
grep -q 'acquire_lock doctor' "$ROOT/scripts/checks/doctor.sh" && ok "doctor-locks" "doctor takes the lock" || bad "doctor-locks" "doctor does not take the lock"
! grep -q 'mkdir "\$lock"' "$ROOT/.githooks/pre-push" && ok "one-impl" "pre-push has no lock of its own" || bad "one-impl" "pre-push still carries a second lock implementation"

if [ "$fail" -eq 0 ]; then echo "PASS test-lock"; else echo "FAIL test-lock" >&2; exit 1; fi
