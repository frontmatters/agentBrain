#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-claims.sh — the behaviours SPEC-claims.md promises, pinned.
#
# Each case exists because getting it wrong is silent. A claim system that says
# "nothing held" while something is held is worse than no claim system at all:
# an empty answer looks like an answer.
#
# Runs entirely inside a temp AGENTBRAIN_DIR, so it never touches a real vault.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../../.." && pwd)"
BIN="$ROOT_DIR/system/addons/event-bus/bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export AGENTBRAIN_DIR="$TMP"
mkdir -p "$TMP/vault/events"
# brain-emit derives event ids with uuid5, so the namespace must be a real UUID.
printf '{"namespace":"6ba7b810-9dad-11d1-80b4-00c04fd430c8"}\n' > "$TMP/brain.json"

pass=0; fail=0
ok()    { pass=$((pass+1)); echo "ok   $1"; }
bad()   { fail=$((fail+1)); echo "FAIL $1" >&2; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2' want '$3')"; fi; }
count() { ls "$TMP/vault/claims"/*.json 2>/dev/null | wc -l | tr -d ' '; }
# Events of one type in the inbox, and whether each one carries a claim record.
events() { grep -l "\"type\": \"$1\"" "$TMP/vault/events/inbox"/*.json 2>/dev/null | wc -l | tr -d ' '; }
event_intent() { grep -l "\"type\": \"$1\"" "$TMP/vault/events/inbox"/*.json 2>/dev/null | xargs -I{} jq -r '.payload.intent' {} | grep -cx "$2" || true; }
field() { grep -l "\"intent\": \"$1\"" "$TMP/vault/claims"/*.json 2>/dev/null | head -1 | xargs -I{} jq -r ".$2" {}; }

BRAIN_AGENT=s1 "$BIN/brain-claim" "werk a" --paths=src/a >/dev/null 2>&1
check "no overlap exits 0" "$?" "0"

out="$(BRAIN_AGENT=s2 "$BIN/brain-claim" "werk b" --paths=src/ 2>&1)"; rc=$?
check "path overlap exits 3" "$rc" "3"
case "$out" in *"path overlap"*) ok "path overlap warns" ;; *) bad "path overlap warns" ;; esac
check "overlapping claim is still recorded" "$(count)" "2"

BRAIN_AGENT=s3 "$BIN/brain-claim" "werk c" --paths=docs/ >/dev/null 2>&1
check "unrelated path exits 0" "$?" "0"

BRAIN_AGENT=s4 "$BIN/brain-claim" "verlopen" --ttl=0 >/dev/null 2>&1
before="$(count)"
check "expired claim is not listed" "$("$BIN/brain-claims" 2>/dev/null | grep -c verlopen || true)" "0"
check "reading does not delete" "$(count)" "$before"

"$BIN/brain-claims" --gc >/dev/null 2>&1
check "gc removes the expired claim" "$(count)" "$((before - 1))"

n1="$(count)"
BRAIN_AGENT=s1 "$BIN/brain-claim" "werk a" --paths=src/a --ttl=6h >/dev/null 2>&1
check "re-claim does not duplicate" "$(count)" "$n1"

BRAIN_AGENT=session-xyz "$BIN/brain-claim" "identiteit" --paths=zzz/ >/dev/null 2>&1
check "agent is the session, not the user" "$(field identiteit agent)" "session-xyz"

printf '{"claim_expiry_hours": 2}\n' > "$TMP/vault/events/config.json"
BRAIN_AGENT=s9 "$BIN/brain-claim" "config" --paths=cfg/ >/dev/null 2>&1
h="$(field config expires_at)"; t="$(field config taken_at)"
check "config sets the expiry" \
  "$(python3 -c "
import sys,datetime
f=lambda s: datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
print(round((f(sys.argv[1])-f(sys.argv[2])).total_seconds()/3600))" "$h" "$t")" "2"

BRAIN_AGENT=s9 "$BIN/brain-claim" "vlag" --paths=vlag/ --ttl=1h >/dev/null 2>&1
h2="$(field vlag expires_at)"; t2="$(field vlag taken_at)"
check "flag beats config" \
  "$(python3 -c "
import sys,datetime
f=lambda s: datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
print(round((f(sys.argv[1])-f(sys.argv[2])).total_seconds()/3600))" "$h2" "$t2")" "1"

id="$(field identiteit id)"
"$BIN/brain-claim" --release "$id" >/dev/null 2>&1
check "release removes the claim" "$(field identiteit id)" ""

# History: SPEC-claims.md promises one event per taken/released/expired claim.
# Before this was pinned, brain-claim called brain-emit with flags it does not
# parse and no recipient, and hid the error: every claim "worked" and the log
# stayed empty. Taken: werk a, werk b, werk c, verlopen, identiteit, config,
# vlag = 7 (the re-claim of werk a extends and emits nothing, per the spec).
check "work.claim.taken lands in the inbox, once per new claim" "$(events work.claim.taken)" "7"
check "taken event carries the claim record" "$(event_intent work.claim.taken identiteit)" "1"
check "work.claim.expired lands in the inbox" "$(events work.claim.expired)" "1"
check "expired event carries the claim record" "$(event_intent work.claim.expired verlopen)" "1"
check "work.claim.released lands in the inbox" "$(events work.claim.released)" "1"
check "released event carries the claim record" "$(event_intent work.claim.released identiteit)" "1"
check "claim events are broadcast" \
  "$(jq -r '.to.broadcast' "$TMP/vault/events/inbox"/*work-claim-*.json | sort -u)" "true"

# Best-effort, not silent: a broken event log must not fail the claim, and must
# say so on stderr.
mv "$TMP/brain.json" "$TMP/brain.json.off"
err="$(BRAIN_AGENT=s10 "$BIN/brain-claim" "zonder log" --paths=nolog/ 2>&1 >/dev/null)"; rc=$?
check "a failed emit does not fail the claim" "$rc" "0"
check "the claim is still recorded when the emit fails" "$(field 'zonder log' agent)" "s10"
case "$err" in *"not written to the event log"*) ok "a failed emit is reported on stderr" ;; *) bad "a failed emit is reported on stderr (got '$err')" ;; esac
mv "$TMP/brain.json.off" "$TMP/brain.json"

echo "test-claims: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
