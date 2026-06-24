#!/usr/bin/env bash
# smoke-test.sh — End-to-end smoke tests for agentBrain.
#
# Doctor checks structural invariants (files exist, schemas valid).
# This script checks behavioural invariants (the thing actually works):
#   - brain.sh flip-mechanism is alive and round-trips
#   - Pi extensions resolve via the alias (not hardcoded paths)
#   - Both checkouts have a working brain-paths.ts after deploy
#   - Event-bus emit+poll roundtrips in both dev and live binaries
#   - Doctor passes in both checkouts
#
# Non-destructive: saves the current flip state and restores it on exit.
#
# Exit codes:
#   0  all tests passed
#   1  one or more tests failed
#   2  prerequisite missing (brain.sh, bun, jq)

set -uo pipefail

DEV_DIR="${DEV_DIR:-$HOME/Developer/agentBrain-dev}"
LIVE_DIR="${LIVE_DIR:-$HOME/Developer/agentBrain}"
ALIAS="$HOME/agentBrain"

PASS=0
FAIL=0
TESTS=()

# ── Prereqs ──
for cmd in bun jq; do
	command -v "$cmd" >/dev/null 2>&1 || { echo "smoke-test: missing prereq: $cmd" >&2; exit 2; }
done
[ -x "$DEV_DIR/scripts/brain.sh" ] || { echo "smoke-test: brain.sh missing at $DEV_DIR" >&2; exit 2; }

# ── Save flip state to restore on exit ──
ORIGINAL_TARGET="$(readlink "$ALIAS" 2>/dev/null || true)"
# shellcheck disable=SC2329  # invoked indirectly via trap below
restore_flip() {
	if [ -n "$ORIGINAL_TARGET" ] && [ "$(readlink "$ALIAS" 2>/dev/null || true)" != "$ORIGINAL_TARGET" ]; then
		ln -sfn "$ORIGINAL_TARGET" "$ALIAS"
		echo ""
		echo "smoke-test: restored alias → $ORIGINAL_TARGET"
	fi
	rm -f /tmp/smoke-test-brain-paths-*.ts
}
trap restore_flip EXIT

# ── Test helpers ──
record() {
	local name="$1" status="$2" detail="${3:-}"
	if [ "$status" = "pass" ]; then
		PASS=$((PASS + 1))
		printf "  ✓ %s\n" "$name"
	else
		FAIL=$((FAIL + 1))
		printf "  ✗ %s — %s\n" "$name" "$detail"
	fi
	TESTS+=("$status:$name")
}

probe_brain_dir() {
	# Imports a brain-paths.ts and prints the resolved BRAIN_DIR.
	# $1 = absolute path to brain-paths.ts
	local script
	script="/tmp/smoke-test-brain-paths-$$.ts"
	printf 'import { BRAIN_DIR } from "%s";\nconsole.log(BRAIN_DIR);\n' "$1" > "$script"
	bun run "$script" 2>/dev/null | tail -1
}

# ── Run tests ──
echo "agentBrain smoke test"
echo "====================="
echo ""

# 1. brain status reachable
echo "[1/9] brain status"
if bash "$DEV_DIR/scripts/brain.sh" status >/dev/null 2>&1; then
	record "brain status returns 0" pass
else
	record "brain status returns 0" fail "non-zero exit"
fi

# 2. Pi (dev) resolves via alias, not hardcoded path
echo "[2/9] Pi (dev) brain-paths resolves via alias"
DEV_BRAIN_DIR="$(probe_brain_dir "$DEV_DIR/system/pi-config/extensions/brain-paths.ts")"
if [ "$DEV_BRAIN_DIR" = "$ALIAS" ]; then
	record "dev brain-paths → $ALIAS" pass
else
	record "dev brain-paths → expected $ALIAS, got '$DEV_BRAIN_DIR'" fail "$DEV_BRAIN_DIR"
fi

# 3. brain use flips the symlink
echo "[3/9] brain use live flips symlink"
bash "$DEV_DIR/scripts/brain.sh" use live >/dev/null 2>&1
if [ "$(readlink "$ALIAS")" = "$LIVE_DIR" ]; then
	record "alias → $LIVE_DIR after 'brain use live'" pass
else
	record "alias did not flip to live" fail "$(readlink "$ALIAS")"
fi

# 4. Pi still resolves via alias after flip (runtime, not cached)
echo "[4/9] Pi resolution is runtime, not cached"
FLIPPED_BRAIN_DIR="$(probe_brain_dir "$DEV_DIR/system/pi-config/extensions/brain-paths.ts")"
if [ "$FLIPPED_BRAIN_DIR" = "$ALIAS" ]; then
	record "BRAIN_DIR still = $ALIAS after flip" pass
else
	record "BRAIN_DIR diverged after flip" fail "$FLIPPED_BRAIN_DIR"
fi

# 5. Live's deployed brain-paths.ts has the same fix
echo "[5/9] Live brain-paths.ts is the patched version"
LIVE_BRAIN_DIR="$(probe_brain_dir "$LIVE_DIR/system/pi-config/extensions/brain-paths.ts")"
if [ "$LIVE_BRAIN_DIR" = "$ALIAS" ]; then
	record "live brain-paths → $ALIAS" pass
else
	record "live brain-paths still hardcoded" fail "$LIVE_BRAIN_DIR"
fi

# 6. Flip back to dev
echo "[6/9] brain use dev flips back"
bash "$DEV_DIR/scripts/brain.sh" use dev >/dev/null 2>&1
if [ "$(readlink "$ALIAS")" = "$DEV_DIR" ]; then
	record "alias → $DEV_DIR after 'brain use dev'" pass
else
	record "alias did not flip back to dev" fail "$(readlink "$ALIAS")"
fi

# 7. Event-bus roundtrip via dev binary
echo "[7/9] event-bus emit+poll via dev binary"
DEV_EMIT="$DEV_DIR/system/addons/event-bus/bin/brain-emit"
DEV_POLL="$DEV_DIR/system/addons/event-bus/bin/brain-poll"
DEV_PING_ID="$("$DEV_EMIT" --type=system.bus.ping --broadcast --payload='{"smoke":"dev"}' 2>/dev/null)"
DEV_MATCH="$("$DEV_POLL" --agent=claude --type='system.bus.ping' --lookback=1m --raw --all 2>/dev/null \
	| jq -r --arg id "$DEV_PING_ID" 'select(.event_id == $id) | .event_id' 2>/dev/null)"
if [ "$DEV_MATCH" = "$DEV_PING_ID" ]; then
	record "dev: emit+poll roundtrip ($DEV_PING_ID)" pass
else
	record "dev: emit OK but poll did not return event" fail "$DEV_PING_ID"
fi

# 8. Event-bus roundtrip via live binary (deployed addon)
echo "[8/9] event-bus emit+poll via live binary"
LIVE_EMIT="$LIVE_DIR/system/addons/event-bus/bin/brain-emit"
LIVE_POLL="$LIVE_DIR/system/addons/event-bus/bin/brain-poll"
if [ -x "$LIVE_EMIT" ] && [ -x "$LIVE_POLL" ]; then
	LIVE_PING_ID="$("$LIVE_EMIT" --type=system.bus.ping --broadcast --payload='{"smoke":"live"}' 2>/dev/null)"
	LIVE_MATCH="$("$LIVE_POLL" --agent=claude --type='system.bus.ping' --lookback=1m --raw --all 2>/dev/null \
		| jq -r --arg id "$LIVE_PING_ID" 'select(.event_id == $id) | .event_id' 2>/dev/null)"
	if [ "$LIVE_MATCH" = "$LIVE_PING_ID" ]; then
		record "live: emit+poll roundtrip ($LIVE_PING_ID)" pass
	else
		record "live: emit+poll roundtrip" fail "no match for $LIVE_PING_ID"
	fi
else
	record "live: event-bus binaries present" fail "missing at $LIVE_EMIT"
fi

# 9. Doctor in both checkouts
echo "[9/9] doctor in dev + live"
if bash "$DEV_DIR/scripts/doctor.sh" >/dev/null 2>&1; then
	record "dev doctor passes" pass
else
	record "dev doctor passes" fail "non-zero exit"
fi
if bash "$LIVE_DIR/scripts/doctor.sh" >/dev/null 2>&1; then
	record "live doctor passes" pass
else
	record "live doctor passes" fail "non-zero exit"
fi

# ── Summary ──
echo ""
echo "====================="
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
	echo "smoke-test: ✅ $PASS/$TOTAL passed"
	exit 0
else
	echo "smoke-test: ❌ $FAIL/$TOTAL failed"
	exit 1
fi
