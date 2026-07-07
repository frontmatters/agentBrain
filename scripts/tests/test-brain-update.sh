#!/usr/bin/env bash
# Tests for brain-update.sh using throwaway git repos. No network, no real brain.
# Proves: up-to-date no-op, fast-forward behind a green doctor gate, and the
# critical rollback-to-anchor when the gate is red.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/../brain-update.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
gq()  { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# Channel config: prerelease channel, branch mode, branches.prerelease=next.
export AGENTBRAIN_DIR="$TMP/brain"
mkdir -p "$AGENTBRAIN_DIR/local/update"
cat > "$AGENTBRAIN_DIR/local/update/config.json" <<'JSON'
{ "channel": "prerelease", "mode": "branch", "source": "origin",
  "branches": { "edge": "main", "prerelease": "next", "stable": "stable" } }
JSON

# Fixture: bare origin + a work clone sitting on branch 'next'.
ORIGIN="$TMP/origin.git"; WORK="$TMP/work"
git init --quiet --bare "$ORIGIN"
git clone --quiet "$ORIGIN" "$WORK"
git -C "$WORK" config user.email t@t.t; git -C "$WORK" config user.name t
git -C "$WORK" config commit.gpgsign false
echo "1.0.0" > "$WORK/VERSION"; echo "base" > "$WORK/file.txt"
gq "$WORK" add .; gq "$WORK" commit -m init; gq "$WORK" push -u origin HEAD
gq "$WORK" branch -m next 2>/dev/null || gq "$WORK" checkout -b next
gq "$WORK" push -u origin next

run() { AGENTBRAIN_DIR="$AGENTBRAIN_DIR" AGENTBRAIN_DEV_DIR="$WORK" bash "$BIN" "$@"; }

# ── A: up to date ───────────────────────────────────────────────────────────
rc=0; out="$(run --repo "$WORK" --doctor-cmd true 2>&1)" || rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "up to date"; then
  ok "up to date -> no-op, exit 0"
else bad "up to date"; echo "$out"; fi

# Advance origin/next by one commit (a 'release' from elsewhere).
SECOND="$TMP/second"; git clone --quiet -b next "$ORIGIN" "$SECOND"
git -C "$SECOND" config user.email t@t.t; git -C "$SECOND" config user.name t
git -C "$SECOND" config commit.gpgsign false
echo "1.1.0" > "$SECOND/VERSION"; echo "release" >> "$SECOND/file.txt"
gq "$SECOND" add .; gq "$SECOND" commit -m "newer release"; gq "$SECOND" push

# ── B: --check reports available, changes nothing ───────────────────────────
before="$(git -C "$WORK" rev-parse HEAD)"
rc=0; out="$(run --repo "$WORK" --check 2>&1)" || rc=$?
after="$(git -C "$WORK" rev-parse HEAD)"
if [ "$rc" -eq 10 ] && echo "$out" | grep -q "update available" && [ "$before" = "$after" ]; then
  ok "--check -> exit 10, nothing changed"
else bad "--check"; echo "rc=$rc $out"; fi

# ── C: fast-forward behind a GREEN doctor gate ──────────────────────────────
rc=0; out="$(run --repo "$WORK" --doctor-cmd true 2>&1)" || rc=$?
ver="$(cat "$WORK/VERSION")"
if [ "$rc" -eq 0 ] && [ "$ver" = "1.1.0" ] && echo "$out" | grep -q "updated to"; then
  ok "green gate -> fast-forwarded to the release (VERSION 1.1.0)"
else bad "green gate ff"; echo "rc=$rc ver=$ver $out"; fi

# Advance origin again for the rollback test.
echo "1.2.0" > "$SECOND/VERSION"; gq "$SECOND" add .; gq "$SECOND" commit -m v120; gq "$SECOND" push
anchor="$(git -C "$WORK" rev-parse HEAD)"

# ── D: RED doctor gate -> rollback to the exact anchor ──────────────────────
rc=0; out="$(run --repo "$WORK" --doctor-cmd false 2>&1)" || rc=$?
now="$(git -C "$WORK" rev-parse HEAD)"; ver="$(cat "$WORK/VERSION")"
if [ "$rc" -ne 0 ] && [ "$now" = "$anchor" ] && [ "$ver" = "1.1.0" ] && echo "$out" | grep -qi "rolled back"; then
  ok "red gate -> rolled back to anchor (still 1.1.0)"
else bad "red gate rollback"; echo "rc=$rc now=$now anchor=$anchor ver=$ver"; echo "$out"; fi

# ── E: dirty working tree -> abort, no update ───────────────────────────────
echo "dirty" >> "$WORK/file.txt"
rc=0; out="$(run --repo "$WORK" --doctor-cmd true 2>&1)" || rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qi "not clean"; then
  ok "dirty tree -> abort, nothing changed"
else bad "dirty tree abort"; echo "rc=$rc $out"; fi
gq "$WORK" checkout -- file.txt

# ── --session modes (auto_update: off / notify / auto) ──────────────────────
# Fresh work clone one release behind origin/next.
W2="$TMP/work2"; git clone --quiet -b next "$ORIGIN" "$W2"
gq "$W2" reset --hard HEAD~2   # 2 commits behind the tip (1.1.0 + 1.2.0 landed above)
mkcfg() { python3 -c "import json;p='$AGENTBRAIN_DIR/local/update/config.json';d=json.load(open(p));d['auto_update']='$1';json.dump(d,open(p,'w'))"; }
ses() { AGENTBRAIN_DIR="$AGENTBRAIN_DIR" AGENTBRAIN_DEV_DIR="$W2" BRAIN_UPDATE_DOCTOR=true BRAIN_UPDATE_INTERVAL_H=0 bash "$BIN" --session --repo "$W2"; }

before="$(git -C "$W2" rev-parse HEAD)"
mkcfg off
rc=0; out="$(ses 2>&1)" || rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$W2" rev-parse HEAD)" = "$before" ] && [ -z "$out" ] \
  && ok "session off -> silent no-op" || { bad "session off"; echo "rc=$rc '$out'"; }

mkcfg notify
rc=0; out="$(ses 2>&1)" || rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "update available" && [ "$(git -C "$W2" rev-parse HEAD)" = "$before" ] \
  && ok "session notify -> reports, changes nothing, exit 0" || { bad "session notify"; echo "rc=$rc '$out'"; }

mkcfg ask
rc=0; out="$(ses 2>&1)" || rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "Ask the user whether to update" && [ "$(git -C "$W2" rev-parse HEAD)" = "$before" ] \
  && ok "session ask (no TTY) -> hands off to the agent, changes nothing, exit 0" || { bad "session ask"; echo "rc=$rc '$out'"; }

mkcfg auto
rc=0; ses >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && [ "$(git -C "$W2" rev-parse HEAD)" != "$before" ] \
  && ok "session auto -> updates behind the gate, exit 0" || { bad "session auto"; echo "rc=$rc"; }

# ── --session rate-limit: a fresh stamp suppresses the next run ──────────────
gq "$W2" reset --hard HEAD~1   # behind again so an update is available
mkcfg notify
date +%s > "$AGENTBRAIN_DIR/local/update/.last-session-check"   # just checked
rl="$(AGENTBRAIN_DIR="$AGENTBRAIN_DIR" AGENTBRAIN_DEV_DIR="$W2" BRAIN_UPDATE_DOCTOR=true BRAIN_UPDATE_INTERVAL_H=12 bash "$BIN" --session --repo "$W2" 2>&1)"
[ -z "$rl" ] && ok "session rate-limit -> suppressed within the interval" \
  || { bad "session rate-limit"; echo "'$rl'"; }

echo ""
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
