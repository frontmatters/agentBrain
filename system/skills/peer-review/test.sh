#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# peer-review v2 test suite — exercises the four modes with the echo-LLM stub.
# No real LLM calls; no network.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SKILL_DIR/bin/peer-review"
HOST_NAME="$(hostname -s)"

# Run entirely inside a throwaway sandbox so the suite never writes its test
# events (echo-stub reviews, test-pr-* agents) into the REAL vault's event-bus
# inbox — that pollution is what filled local/events/inbox with thousands of
# stub events. The peer-review + event-bus bins resolve every data dir from
# AGENTBRAIN_DIR, so we point it at a fresh temp dir and symlink the real
# system/ in for the bin tools. Mirrors event-bus/tests/test-event-bus.sh.
REAL_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
SANDBOX="$(mktemp -d)"
ln -s "$REAL_ROOT/system" "$SANDBOX/system"
mkdir -p "$SANDBOX/local"
# brain-emit validates the checkout by reading $AGENTBRAIN_DIR/brain.json (it
# only needs .namespace for event-id generation), so give the sandbox one — same
# approach as event-bus/tests/test-event-bus.sh.
cat > "$SANDBOX/brain.json" <<'EOF'
{ "namespace": "e37d107c-934a-4626-806e-8da1b442c8e4", "version": "1.0" }
EOF
export AGENTBRAIN_DIR="$SANDBOX"
trap 'rm -rf "$SANDBOX"; rm -f "${TESTDOC:-}" "${OUTFILE:-}"' EXIT

pass=0
fail=0

ok() { printf "  ✓ %s\n" "$1"; pass=$((pass + 1)); }
no() { printf "  ✗ %s\n" "$1"; fail=$((fail + 1)); }

echo "peer-review v2 test.sh"

# T1: --help
if "$BIN" --help 2>&1 | grep -q "peer-review v2"; then
    ok "--help shows v2 banner"
else
    no "--help missing v2 banner"
fi

# T2: missing doc for request mode (capture first; BIN exits 1 + pipefail would otherwise fail the if)
T2_OUT="$("$BIN" 2>&1 || true)"
if echo "$T2_OUT" | grep -q "doc.*required"; then
    ok "missing-doc rejected with clear message"
else
    no "missing-doc not rejected properly (got: $T2_OUT)"
fi

# T3: --list runs cleanly
if "$BIN" --list --from=tester --lookback=1d >/dev/null 2>&1; then
    ok "--list runs cleanly"
else
    no "--list errored"
fi

# T4: full echo round-trip
TESTDOC="$(mktemp -t peer-review-test.XXXXXX.md)"
cat > "$TESTDOC" <<'EOF'
# Tiny test doc
content
EOF
# TESTDOC cleanup is handled by the sandbox EXIT trap set at the top.

# Fresh cursors (now sandbox-local, so this no longer defeats real-bus dedup)
rm -f "$AGENTBRAIN_DIR/vault/events/cursors/$HOST_NAME/test-pr-reviewer/seen-ids.set"
rm -f "$AGENTBRAIN_DIR/vault/events/cursors/$HOST_NAME/test-pr-requester/seen-ids.set"

# stderr is kept, not discarded. This assertion has failed inside release gates
# on three occasions and was undiagnosable every time, because the reason went
# to /dev/null here and the sandbox was deleted before anyone could look. The
# test that reports the failure is the only place that still holds the evidence.
REQ_ERR="$SANDBOX/request.err"
# This file runs with set -e, so the call needs a guard or a failure ends the
# whole test. "|| true" was that guard, and it also made $? the status of the
# guard: the exit code was unrecoverable. Assigning inside the || keeps the
# script alive and keeps the real code.
REQ_ID=""; REQ_RC=0
REQ_ID="$("$BIN" "$TESTDOC" --to=test-pr-reviewer --from=test-pr-requester 2>"$REQ_ERR")" || REQ_RC=$?
if [ -n "$REQ_ID" ] && [[ "$REQ_ID" =~ ^[0-9a-f-]{36}$ ]]; then
    ok "request mode emits event_id ($REQ_ID)"
else
    no "request mode failed to emit valid event_id (got: $REQ_ID)"
    printf '      exit %s from %s\n' "$REQ_RC" "$BIN" >&2
    printf '      AGENTBRAIN_DIR=%s\n' "$AGENTBRAIN_DIR" >&2
    # Facts, not a re-derivation: sourcing vault.sh here failed silently and
    # printed a question mark, which is worse than printing nothing.
    printf '      brain.json %s | vault/ %s | local/ %s | inbox %s\n' \
        "$([ -f "$AGENTBRAIN_DIR/brain.json" ] && echo present || echo MISSING)" \
        "$([ -d "$AGENTBRAIN_DIR/vault" ] && echo present || echo absent)" \
        "$([ -d "$AGENTBRAIN_DIR/local" ] && echo present || echo absent)" \
        "$([ -d "$AGENTBRAIN_DIR/vault/events/inbox" ] && echo present || echo MISSING)" >&2
    printf '      jq %s | PATH=%s\n' "$(command -v jq || echo MISSING)" "$PATH" >&2
    if [ -s "$REQ_ERR" ]; then
        printf '      stderr:\n' >&2
        sed 's/^/        /' "$REQ_ERR" >&2
    else
        printf '      stderr: empty\n' >&2
    fi
fi

# T5: consume --once picks up + emits completed
CONSUME_OUT="$("$BIN" --consume --as=test-pr-reviewer --llm=echo --once 2>&1 || true)"
if echo "$CONSUME_OUT" | grep -q "emitted completed for $REQ_ID"; then
    ok "consume mode emits completed"
else
    no "consume mode did NOT emit completed for $REQ_ID"
fi

# T6: list filtered by correlation shows the completed
# stderr kept, same reason as T4: this assertion has failed inside a release gate
# with nothing to say for itself. The window is a string comparison on the
# filename timestamp, so the inbox listing and the archive listing are the two
# things worth seeing next to the query.
LIST_ERR="$SANDBOX/list.err"
LIST_OUT=""; LIST_RC=0
LIST_OUT="$("$BIN" --list --type=completed --correlation="$REQ_ID" --from=test-pr-requester --lookback=1h 2>"$LIST_ERR")" || LIST_RC=$?
if echo "$LIST_OUT" | grep -q "peer-review.review.completed"; then
    ok "--list --correlation finds the completed"
else
    no "--list --correlation didn't find the completed"
    printf '      exit %s, correlation=%s\n' "$LIST_RC" "$REQ_ID" >&2
    printf '      now(UTC) %s\n' "$(date -u '+%Y%m%dT%H%M%S')" >&2
    printf '      inbox:\n' >&2
    ls -1 "$AGENTBRAIN_DIR/vault/events/inbox" 2>/dev/null | sed 's/^/        /' >&2 || printf '        (none)\n' >&2
    printf '      archive:\n' >&2
    find "$AGENTBRAIN_DIR/vault/events/archive" -type f -name '*.json' 2>/dev/null | sed "s|^.*/|        |" >&2 || printf '        (none)\n' >&2
    printf '      list stdout: %s\n' "${LIST_OUT:-(empty)}" >&2
    if [ -s "$LIST_ERR" ]; then printf '      stderr:\n' >&2; sed 's/^/        /' "$LIST_ERR" >&2; fi
    fi

# T7: archive renders correctly
COMP_ID="$(echo "$LIST_OUT" | jq -r '.event_id' | head -1 || true)"
if [ -n "$COMP_ID" ] && [ "$COMP_ID" != "null" ]; then
    OUTFILE="$(mktemp -t peer-review-archive.XXXXXX.md)"
    "$BIN" --archive "$COMP_ID" --from=test-pr-requester --out="$OUTFILE" >/dev/null 2>&1
    if [ -f "$OUTFILE" ] && grep -q "^# Review of" "$OUTFILE"; then
        ok "archive renders to expected format"
        rm -f "$OUTFILE"
    else
        no "archive missing expected content"
    fi
else
    no "no completed event found to archive"
fi

# T8: bad --llm spec rejected (no real LLM run) — consume starts but errors per-request
if "$BIN" --consume --as=test-pr-reviewer --llm=nonexistent-backend --once 2>&1 | head -1 | grep -q "consuming"; then
    ok "consume mode starts with unknown --llm spec (errors only on real request)"
else
    no "consume mode failed to start"
fi

echo ""

# T9: --heartbeat=garbage validation falls back to default + warns
T9_OUT="$("$BIN" "$TESTDOC" --to=nobody-test --from=tester --wait=1 --heartbeat=garbage 2>&1 || true)"
if echo "$T9_OUT" | grep -q "invalid heartbeat 'garbage'"; then
    ok "--heartbeat=garbage rejected with fallback warning"
else
    no "--heartbeat input validation missing (got: $T9_OUT)"
fi

# T10: --heartbeat=0 disables heartbeat (silent until timeout)
T10_OUT="$("$BIN" "$TESTDOC" --to=nobody-test --from=tester --wait=2 --heartbeat=0 2>&1 || true)"
if ! echo "$T10_OUT" | grep -q "still waiting"; then
    ok "--heartbeat=0 disables heartbeat output"
else
    no "--heartbeat=0 still printed heartbeat (got: $T10_OUT)"
fi

# T11: --heartbeat documented in --help
if "$BIN" --help 2>&1 | grep -q -- "--heartbeat"; then
    ok "--heartbeat documented in --help"
else
    no "--heartbeat missing from --help"
fi

echo ""
echo "peer-review test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
