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

# A LIVE holder keeps its lock past the stale limit. This is the one that was
# broken: mkdir stamps the mtime once, so a run outlasting $stale handed its
# lock to whoever was waiting, and then two ran at once over the same fixtures.
# The full doctor takes over ten minutes against a 300s default, so it lost its
# lock every single time something else was waiting.
mkdir "$LOCKDIR/agentbrain-live.lock"
sleep 30 & LIVE_PID=$!
printf '%s\n' "$LIVE_PID" > "$LOCKDIR/agentbrain-live.lock/pid"
touch -t 202001010000 "$LOCKDIR/agentbrain-live.lock"   # ancient by the old rule
t0=$(date +%s)
( TMPDIR="$LOCKDIR"; . "$ROOT/scripts/lib/lock.sh"; acquire_lock live 2 1 2>/dev/null )
got=$?
[ "$got" -ne 0 ] && ok "live-holder" "a live holder keeps its lock past the stale limit" \
                 || bad "live-holder" "stole the lock from a process that is still running"

# ...and the moment that holder dies, the lock is free. Liveness cuts both
# ways, or "stale" just becomes "never".
kill "$LIVE_PID" 2>/dev/null; wait "$LIVE_PID" 2>/dev/null
t0=$(date +%s)
( TMPDIR="$LOCKDIR"; . "$ROOT/scripts/lib/lock.sh"; acquire_lock live 10 1 2>/dev/null ) \
  && [ $(( $(date +%s) - t0 )) -le 3 ] \
  && ok "dead-holder" "a dead holder's lock is taken at once" \
  || bad "dead-holder" "a dead holder's lock kept blocking"

# The waiter must be able to say who it is waiting for. A lock with no holder
# in it cannot be told apart from a crashed one, and cannot be reported.
mkdir -p "$LOCKDIR/agentbrain-who.lock"
sleep 5 & WHO_PID=$!
printf '%s\n' "$WHO_PID" > "$LOCKDIR/agentbrain-who.lock/pid"
msg="$( TMPDIR="$LOCKDIR"; . "$ROOT/scripts/lib/lock.sh"; acquire_lock who 1 999 2>&1 >/dev/null )"
kill "$WHO_PID" 2>/dev/null; wait "$WHO_PID" 2>/dev/null
rm -rf "$LOCKDIR/agentbrain-who.lock"
grep -q "pid $WHO_PID" <<<"$msg" && ok "names-holder" "the wait message names the holding pid" \
                                 || bad "names-holder" "the wait message does not say who holds it: $msg"

# The library states a fact; what to do about it is the caller's call. It used
# to say "proceeding without it" while doctor read the same return code as a
# reason to stop.
grep -q 'proceeding without it' "$ROOT/scripts/lib/lock.sh" \
  && bad "one-contract" "lock.sh still tells the caller what to do" \
  || ok "one-contract" "lock.sh reports, the caller decides"

# A child of the holder must not wait on its parent: doctor runs tests that
# run doctor.
t0=$(date +%s)
( TMPDIR="$LOCKDIR"; export TMPDIR; . "$ROOT/scripts/lib/lock.sh"; acquire_lock r 10; bash -c ". '$ROOT/scripts/lib/lock.sh'; acquire_lock r 10" ) 2>/dev/null
[ $(( $(date +%s) - t0 )) -le 1 ] && ok "reentrant" "a nested run under the holder proceeds at once" || bad "reentrant" "a nested run waited on its own ancestor"

# doctor and the pre-push hook use it.
grep -q 'acquire_lock doctor' "$ROOT/scripts/checks/doctor.sh" && ok "doctor-locks" "doctor takes the lock" || bad "doctor-locks" "doctor does not take the lock"
! grep -q 'mkdir "\$lock"' "$ROOT/.githooks/pre-push" && ok "one-impl" "pre-push has no lock of its own" || bad "one-impl" "pre-push still carries a second lock implementation"

if [ "$fail" -eq 0 ]; then echo "PASS test-lock"; else echo "FAIL test-lock" >&2; exit 1; fi
