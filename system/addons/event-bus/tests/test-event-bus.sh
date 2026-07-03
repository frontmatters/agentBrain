#!/usr/bin/env bash
# Behavioural tests for the event-bus addon. Runs entirely against a tmpdir bus
# (AGENTBRAIN_DIR override) — no network, no real local/events/, no install needed.
# Covers: emit->poll roundtrip, envelope validation, routing filter, cursor dedup.
set -euo pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMIT="$ADDON_DIR/bin/brain-emit"
POLL="$ADDON_DIR/bin/brain-poll"

# Dependency guard: the bins need jq + python3 + openssl. If absent, skip cleanly
# (the addons.sh runner only invokes us when bash is on PATH; bins need more).
for dep in jq python3 openssl; do
	if ! command -v "$dep" >/dev/null 2>&1; then
		echo "SKIP: '$dep' not installed — event-bus bins need it" >&2
		exit 0
	fi
done

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
export AGENTBRAIN_DIR="$TEST_DIR"
cat > "$TEST_DIR/brain.json" <<'EOF'
{ "namespace": "e37d107c-934a-4626-806e-8da1b442c8e4", "version": "1.0" }
EOF

passed=0
failed=0
failures=()
assert() {
	local desc="$1" actual="$2" expected="$3"
	if [ "$actual" = "$expected" ]; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		failures+=("$desc: expected '$expected', got '$actual'")
	fi
}

# --- emit -> poll roundtrip ---
eid="$(bash "$EMIT" --type=peer-review.review.requested --to=pi --from=claude --payload='{"q":"sound?"}')"
assert "emit returns a uuid event_id" "$(printf '%s' "$eid" | grep -cE '^[0-9a-f-]{36}$')" "1"
assert "emit writes one inbox file" "$(find "$TEST_DIR/local/events/inbox" -name '*.json' | wc -l | tr -d ' ')" "1"

# brain-poll derives host from `hostname -s`; let it default so cursor path matches.
HOST="$(hostname -s)"
poll_out="$(bash "$POLL" --agent=pi 2>/dev/null)"
assert "poll yields the event for pi" "$(printf '%s' "$poll_out" | grep -c "$eid")" "1"
assert "poll output is one NDJSON line" "$(printf '%s\n' "$poll_out" | grep -c '{')" "1"

# --- routing filter: wrong agent sees nothing ---
other_out="$(bash "$POLL" --agent=gemini 2>/dev/null || true)"
assert "non-addressed agent yields nothing" "$(printf '%s' "$other_out" | grep -c "$eid")" "0"

# --- cursor dedup: --commit then re-poll yields nothing ---
bash "$POLL" --agent=pi --commit >/dev/null 2>&1
recommit_out="$(bash "$POLL" --agent=pi 2>/dev/null || true)"
assert "committed event is not re-yielded" "$(printf '%s' "$recommit_out" | grep -c "$eid")" "0"
assert "seen-ids.set records the id" "$(grep -c "$eid" "$TEST_DIR/local/events/cursors/$HOST/pi/seen-ids.set" 2>/dev/null || echo 0)" "1"
# --all bypasses dedup
all_out="$(bash "$POLL" --agent=pi --all 2>/dev/null || true)"
assert "--all re-yields seen event" "$(printf '%s' "$all_out" | grep -c "$eid")" "1"

# --- broadcast reaches any agent ---
bash "$EMIT" --type=system.bus.announce --broadcast --from=claude --payload='{}' >/dev/null
bc_out="$(bash "$POLL" --agent=someone-new 2>/dev/null || true)"
assert "broadcast reaches arbitrary agent" "$(printf '%s' "$bc_out" | grep -c 'system.bus.announce')" "1"

# --- envelope validation: bad type rejected (exit 2) ---
rc=0; bash "$EMIT" --type=NotValid --to=pi >/dev/null 2>&1 || rc=$?
assert "invalid type format exits 2" "$rc" "2"
# bad JSON payload rejected (exit 3)
rc=0; bash "$EMIT" --type=a.b.c --to=pi --payload='{not json}' >/dev/null 2>&1 || rc=$?
assert "invalid payload JSON exits 3" "$rc" "3"
# missing target rejected (exit 1)
rc=0; bash "$EMIT" --type=a.b.c >/dev/null 2>&1 || rc=$?
assert "missing --to/--broadcast exits 1" "$rc" "1"

# --- poll skips a corrupt envelope without crashing ---
echo 'not json' > "$TEST_DIR/local/events/inbox/$(date -u +%Y%m%dT%H%M%S)-bad-deadbeef.json"
rc=0; bash "$POLL" --agent=pi --all >/dev/null 2>&1 || rc=$?
assert "poll tolerates a corrupt file (exit 0)" "$rc" "0"

# ---- report ----
echo "passed=$passed failed=$failed"
if [ "$failed" -gt 0 ]; then
	printf '%s\n' "${failures[@]}" >&2
	exit 1
fi
