#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-queue.sh — unit tests for scripts/queue.sh (queue+dispatch).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-queue-XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts" "$FIXTURE/local"
cp "$ROOT_DIR/brain.json" "$FIXTURE/"
cp "$ROOT_DIR/scripts/uuid5-gen.sh" "$ROOT_DIR/scripts/validate-note-id.sh" \
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
(cd "$FIXTURE" && bash scripts/validate-note-id.sh "$FIXTURE/$P6" >/dev/null 2>&1) && pass "note still valid after metachar dispatch" || fail "note corrupted (invalid) after metachar dispatch"

# empty title is rejected
if (cd "$FIXTURE" && bash scripts/queue.sh add "" --scope demo >/dev/null 2>&1); then fail "empty title accepted"; else pass "empty title rejected"; fi

# board generates local/queue/index.md with status columns
(cd "$FIXTURE" && bash scripts/queue.sh board >/dev/null)
BRD="$FIXTURE/local/queue/index.md"
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
case "$(cat "$FIXTURE/local/queue/index.md")" in *"$IDP"*) pass "board exposes id" ;; *) fail "board missing id" ;; esac

# slug is dash-joined, no spaces in the filename (BSD/GNU sed portable)
PS="$(cd "$FIXTURE" && bash scripts/queue.sh add "Multi Word Title" --scope slugtest)"
case "$PS" in
  *" "*) fail "slug has spaces: $PS" ;;
  *slugtest/multi-word-title.md) pass "slug is dash-joined" ;;
  *) fail "unexpected slug path: $PS" ;;
esac

echo "queue: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
