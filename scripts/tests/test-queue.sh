#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-queue.sh — unit tests for scripts/queue.sh (queue+dispatch).
# shellcheck disable=SC2015  # `assert && pass || fail` is the intended test-assert idiom here
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-queue-XXXXXX")"
# A fixture brain has the layout setup makes: vault/ is the directory, local/ the alias.
mkdir -p "$FIXTURE/vault" && ln -sfn vault "$FIXTURE/local"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts" "$FIXTURE/local"
cp "$ROOT_DIR/brain.json" "$FIXTURE/"
cp "$ROOT_DIR/scripts/uuid5-gen.sh" "$ROOT_DIR/scripts/hooks/validate-note-id.sh" \
   "$ROOT_DIR/scripts/new-note.sh" "$ROOT_DIR/scripts/queue.sh" "$FIXTURE/scripts/"
PASS=0; FAIL=0
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }

# add creates a pending task note
P="$(cd "$FIXTURE" && bash scripts/queue.sh add "Test login fix" --scope demo --prio P1)"
if [ -f "$FIXTURE/$P" ]; then pass "add creates note"; else fail "add: no note at $P"; fi
if grep -q "^status: pending" "$FIXTURE/$P"; then pass "add status pending"; else fail "add status wrong"; fi
if grep -q "^scope: demo" "$FIXTURE/$P"; then pass "add scope set"; else fail "scope missing"; fi
if grep -q "^priority: P1" "$FIXTURE/$P"; then pass "add priority set"; else fail "priority missing"; fi

# list shows the item
if (cd "$FIXTURE" && bash scripts/queue.sh list --scope demo | grep -q "Test login fix"); then
  pass "list shows item"; else fail "list missing item"; fi

# start flips to in_progress; a second start in same scope flips the first back to pending
ID1="$(grep '^id: ' "$FIXTURE/$P" | awk '{print $2}')"
P2="$(cd "$FIXTURE" && bash scripts/queue.sh add "Second task" --scope demo)"
ID2="$(grep '^id: ' "$FIXTURE/$P2" | awk '{print $2}')"
(cd "$FIXTURE" && bash scripts/queue.sh start "$ID1" >/dev/null)
grep -q "^status: in_progress" "$FIXTURE/$P" && pass "start -> in_progress" || fail "start failed"
(cd "$FIXTURE" && bash scripts/queue.sh start "$ID2" >/dev/null)
grep -q "^status: pending" "$FIXTURE/$P" && pass "invariant: prior in_progress -> pending" || fail "invariant broken"
# done is sticky
(cd "$FIXTURE" && bash scripts/queue.sh "done" "$ID2" >/dev/null)
grep -q "^status: done" "$FIXTURE/$P2" && pass "done set" || fail "done failed"
grep -q "^completed: 20" "$FIXTURE/$P2" && pass "completed stamped" || fail "completed not stamped"
(cd "$FIXTURE" && bash scripts/queue.sh start "$ID2" 2>/dev/null) && fail "sticky broken (reopened done)" || pass "terminal state sticky"

# handoff dispatch sets dispatch field + in_progress (no event bus needed)
P3="$(cd "$FIXTURE" && bash scripts/queue.sh add "Handoff task" --scope demo)"
ID3="$(grep '^id: ' "$FIXTURE/$P3" | awk '{print $2}')"
(cd "$FIXTURE" && bash scripts/queue.sh dispatch "$ID3" --to pi >/dev/null)
grep -q "^dispatch: handoff:pi" "$FIXTURE/$P3" && pass "handoff dispatch set" || fail "handoff failed"
grep -q "^status: in_progress" "$FIXTURE/$P3" && pass "handoff -> in_progress" || fail "handoff status"
# event dispatch calls the emitter (stubbed) with the note id in the payload
STUB="$FIXTURE/emitted.txt"; export QUEUE_EMIT_BIN="$FIXTURE/fake-emit.sh"
printf '#!/bin/sh\necho "$@" >> %s\n' "$STUB" > "$QUEUE_EMIT_BIN"; chmod +x "$QUEUE_EMIT_BIN"
(cd "$FIXTURE" && QUEUE_EMIT_BIN="$QUEUE_EMIT_BIN" bash scripts/queue.sh dispatch "$ID3" --event >/dev/null)
grep -q "queue.item.dispatched" "$STUB" && pass "event emitted with correct type" || fail "no event emitted"
grep -q "$ID3" "$STUB" && pass "event payload carries note id" || fail "payload missing id"

# consume-completions flips the referenced note to done
P4="$(cd "$FIXTURE" && bash scripts/queue.sh add "Consume me" --scope demo)"
ID4="$(grep '^id: ' "$FIXTURE/$P4" | awk '{print $2}')"
export QUEUE_POLL_BIN="$FIXTURE/fake-poll.sh"
cat > "$QUEUE_POLL_BIN" <<STUB
#!/bin/sh
printf '{"type":"queue.item.completed","payload":{"note_id":"%s"}}\n' "$ID4"
STUB
chmod +x "$QUEUE_POLL_BIN"
(cd "$FIXTURE" && QUEUE_POLL_BIN="$QUEUE_POLL_BIN" bash scripts/queue.sh consume-completions >/dev/null)
grep -q "^status: done" "$FIXTURE/$P4" && pass "consumer flips note to done" || fail "consumer did not flip"

# idempotent done: done on an already-done item is a no-op (exit 0), stays done
P5="$(cd "$FIXTURE" && bash scripts/queue.sh add "Idem task" --scope demo)"
ID5="$(grep '^id: ' "$FIXTURE/$P5" | awk '{print $2}')"
(cd "$FIXTURE" && bash scripts/queue.sh "done" "$ID5" >/dev/null)
if (cd "$FIXTURE" && bash scripts/queue.sh "done" "$ID5" >/dev/null 2>&1); then pass "idempotent done is no-op (exit 0)"; else fail "second done errored (should be no-op)"; fi
grep -q "^status: done" "$FIXTURE/$P5" && pass "idempotent done stays done" || fail "status changed after second done"
# cross-terminal is still refused (sticky): cancel on a done item fails
(cd "$FIXTURE" && bash scripts/queue.sh cancel "$ID5" 2>/dev/null) && fail "cross-terminal not refused" || pass "cross-terminal (done->cancel) refused"

# sed-injection safety: an agent name with sed metachars must not corrupt the note
P6="$(cd "$FIXTURE" && bash scripts/queue.sh add "Inject task" --scope demo)"
ID6="$(grep '^id: ' "$FIXTURE/$P6" | awk '{print $2}')"
(cd "$FIXTURE" && bash scripts/queue.sh dispatch "$ID6" --to 'ci|runner&x' >/dev/null 2>&1) || true
grep -q "^dispatch: handoff:ci|runner&x" "$FIXTURE/$P6" && pass "metachar agent stored verbatim" || fail "metachar agent corrupted the note"
(cd "$FIXTURE" && bash "$ROOT_DIR/scripts/hooks/validate-note-id.sh" "$FIXTURE/$P6" >/dev/null 2>&1) && pass "note still valid after metachar dispatch" || fail "note corrupted (invalid) after metachar dispatch"

# empty title is rejected
if (cd "$FIXTURE" && bash scripts/queue.sh add "" --scope demo >/dev/null 2>&1); then fail "empty title accepted"; else pass "empty title rejected"; fi

# board generates local/queue/index.md with status columns
(cd "$FIXTURE" && bash scripts/queue.sh board >/dev/null)
BRD="$FIXTURE/vault/queue/index.md"
[ -f "$BRD" ] && pass "board file created" || fail "no board file"
grep -q "## in_progress" "$BRD" && pass "board has in_progress column" || fail "no in_progress column"
grep -q "## pending" "$BRD" && pass "board has pending column" || fail "no pending column"
grep -q "Consume me\|Handoff task\|Test login fix\|Idem task" "$BRD" && pass "board lists items" || fail "board empty"

# list and board expose the note id (needed to call start/done/dispatch).
# NOTE: match via a captured string, not `list | grep -q` — under `set -o pipefail`
# a `grep -q` that matches an early line closes the pipe and SIGPIPEs `list`
# (exit 141), which pipefail would surface as a false failure.
IDP="$(grep '^id: ' "$FIXTURE/$P" | awk '{print $2}')"
LIST_OUT="$(cd "$FIXTURE" && bash scripts/queue.sh list --scope demo)"
case "$LIST_OUT" in *"$IDP"*) pass "list exposes id" ;; *) fail "list missing id" ;; esac
(cd "$FIXTURE" && bash scripts/queue.sh board >/dev/null)
case "$(cat "$FIXTURE/vault/queue/index.md")" in *"$IDP"*) pass "board exposes id" ;; *) fail "board missing id" ;; esac

# slug is dash-joined, no spaces in the filename (BSD/GNU sed portable)
PS="$(cd "$FIXTURE" && bash scripts/queue.sh add "Multi Word Title" --scope slugtest)"
case "$PS" in
  *" "*) fail "slug has spaces: $PS" ;;
  *slugtest/multi-word-title.md) pass "slug is dash-joined" ;;
  *) fail "unexpected slug path: $PS" ;;
esac

# --- verify: a passing proof stamps `verified`, a failing one refuses done
PV="$(cd "$FIXTURE" && bash scripts/queue.sh add "Verified task" --scope verify --verify "true")"
IDV="$(grep '^id: ' "$FIXTURE/$PV" | awk '{print $2}')"
grep -q "^verify: true" "$FIXTURE/$PV" && pass "add stores verify" || fail "verify not stored"
(cd "$FIXTURE" && bash scripts/queue.sh "done" "$IDV" >/dev/null 2>&1)
grep -q "^status: done" "$FIXTURE/$PV" && pass "passing verify -> done" || fail "passing verify did not finish"
grep -q "^verified: 20" "$FIXTURE/$PV" && pass "verified stamped" || fail "verified not stamped"
PF="$(cd "$FIXTURE" && bash scripts/queue.sh add "Unproven task" --scope verify --verify "test -f nope.txt")"
IDF="$(grep '^id: ' "$FIXTURE/$PF" | awk '{print $2}')"
(cd "$FIXTURE" && bash scripts/queue.sh "done" "$IDF" >/dev/null 2>&1) && fail "failing verify accepted" || pass "failing verify refuses done"
grep -q "^status: pending" "$FIXTURE/$PF" && pass "refused task stays pending" || fail "refused task changed status"
touch "$FIXTURE/nope.txt"
(cd "$FIXTURE" && bash scripts/queue.sh "done" "$IDF" >/dev/null 2>&1) && pass "verify passes once the proof holds" || fail "verify still failing"

# --- blocked_by: only the field blocks; the task wakes when every blocker is done
PA="$(cd "$FIXTURE" && bash scripts/queue.sh add "Blocker A" --scope blk)"
PB="$(cd "$FIXTURE" && bash scripts/queue.sh add "Blocker B" --scope blk)"
IDA="$(grep '^id: ' "$FIXTURE/$PA" | awk '{print $2}')"; IDB="$(grep '^id: ' "$FIXTURE/$PB" | awk '{print $2}')"
PD="$(cd "$FIXTURE" && bash scripts/queue.sh add "Dependent" --scope blk --blocked-by "$IDA,$IDB")"
IDD="$(grep '^id: ' "$FIXTURE/$PD" | awk '{print $2}')"
grep -q "^status: blocked" "$FIXTURE/$PD" && pass "--blocked-by sets blocked" || fail "not blocked"
(cd "$FIXTURE" && bash scripts/queue.sh start "$IDD" >/dev/null 2>&1) && fail "blocked task started" || pass "start refuses blocked task"
(cd "$FIXTURE" && bash scripts/queue.sh "done" "$IDA" >/dev/null)
grep -q "^status: blocked" "$FIXTURE/$PD" && pass "one blocker done: still blocked" || fail "woke too early"
(cd "$FIXTURE" && bash scripts/queue.sh cancel "$IDB" >/dev/null)
grep -q "^status: blocked" "$FIXTURE/$PD" && pass "cancelled blocker keeps it blocked" || fail "cancel woke dependent"
PC="$(cd "$FIXTURE" && bash scripts/queue.sh add "Blocker C" --scope blk)"
IDC="$(grep '^id: ' "$FIXTURE/$PC" | awk '{print $2}')"
(cd "$FIXTURE" && bash scripts/queue.sh block "$IDD" "$IDA,$IDC" >/dev/null)
(cd "$FIXTURE" && bash scripts/queue.sh "done" "$IDC" >/dev/null)
grep -q "^status: pending" "$FIXTURE/$PD" && pass "all blockers done -> pending" || fail "dependent did not wake"
(cd "$FIXTURE" && bash scripts/queue.sh block "$IDD" "no-such-id" >/dev/null 2>&1) && fail "unknown blocker accepted" || pass "unknown blocker id rejected"

# --- watchdog: review parks in in_review; verdict pass -> done, fail -> pending + reason
PW="$(cd "$FIXTURE" && bash scripts/queue.sh add "Watched" --scope wd)"
IDW="$(grep '^id: ' "$FIXTURE/$PW" | awk '{print $2}')"
PR="$(cd "$FIXTURE" && bash scripts/queue.sh add "Rejected" --scope wd)"
IDR="$(grep '^id: ' "$FIXTURE/$PR" | awk '{print $2}')"
: > "$STUB"
(cd "$FIXTURE" && bash scripts/queue.sh review "$IDW" --watchdog pi >/dev/null)
(cd "$FIXTURE" && bash scripts/queue.sh review "$IDR" --watchdog pi >/dev/null)
grep -q "^status: in_review" "$FIXTURE/$PW" && pass "review -> in_review" || fail "review status"
grep -q "queue.item.verify.requested" "$STUB" && pass "verify.requested emitted" || fail "no verify.requested event"
cat > "$QUEUE_POLL_BIN" <<STUB
#!/bin/sh
printf '{"type":"queue.item.verified","payload":{"note_id":"%s","verdict":"pass"}}\n' "$IDW"
printf '{"type":"queue.item.verified","payload":{"note_id":"%s","verdict":"fail","reason":"port 445 still closed"}}\n' "$IDR"
STUB
(cd "$FIXTURE" && bash scripts/queue.sh consume-completions >/dev/null)
grep -q "^status: done" "$FIXTURE/$PW" && pass "verdict pass -> done" || fail "pass verdict ignored"
grep -q "^status: pending" "$FIXTURE/$PR" && pass "verdict fail -> pending" || fail "fail verdict ignored"
grep -q "rejected: port 445 still closed" "$FIXTURE/$PR" && pass "rejection reason logged on note" || fail "no rejection reason"
(cd "$FIXTURE" && bash "$ROOT_DIR/scripts/hooks/validate-note-id.sh" "$FIXTURE/$PR" >/dev/null 2>&1) && pass "note valid after rejection" || fail "note invalid after rejection"

# --- verify policy: broken proof vs false claim, and a recorded override
PO="$(cd "$FIXTURE" && bash scripts/queue.sh add "Override task" --scope policy --verify "false")"
IDO="$(grep '^id: ' "$FIXTURE/$PO" | awk '{print $2}')"
ERR="$(cd "$FIXTURE" && bash scripts/queue.sh "done" "$IDO" 2>&1 >/dev/null || true)"
case "$ERR" in *"not done"*) pass "false claim: 'not done' message" ;; *) fail "false-claim message: $ERR" ;; esac
case "$ERR" in *"QUEUE_FORCE=1"*) pass "refusal names the override" ;; *) fail "override not mentioned" ;; esac
PK="$(cd "$FIXTURE" && bash scripts/queue.sh add "Broken proof" --scope policy --verify "no-such-cmd-xyz")"
IDK="$(grep '^id: ' "$FIXTURE/$PK" | awk '{print $2}')"
ERR="$(cd "$FIXTURE" && bash scripts/queue.sh "done" "$IDK" 2>&1 >/dev/null || true)"
case "$ERR" in *"could not run (exit 127)"*) pass "broken proof: 'could not run' message" ;; *) fail "broken-proof message: $ERR" ;; esac
grep -q "^status: pending" "$FIXTURE/$PK" && pass "broken proof still refuses done" || fail "broken proof marked done"
(cd "$FIXTURE" && QUEUE_FORCE=1 bash scripts/queue.sh "done" "$IDO" >/dev/null 2>&1) && pass "QUEUE_FORCE=1 marks done" || fail "override refused"
grep -q "^status: done" "$FIXTURE/$PO" && pass "override -> done" || fail "override status"
grep -q "^verify_overridden: 20.* exit 1$" "$FIXTURE/$PO" && pass "override recorded with exit code" || fail "override not recorded"
grep -q "^verified:" "$FIXTURE/$PO" && fail "override claims verified" || pass "override does not claim verified"
(cd "$FIXTURE" && bash "$ROOT_DIR/scripts/hooks/validate-note-id.sh" "$FIXTURE/$PO" >/dev/null 2>&1) && pass "note valid after override" || fail "note invalid after override"

echo "queue: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
