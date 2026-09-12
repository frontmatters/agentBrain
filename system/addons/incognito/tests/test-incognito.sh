#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-incognito.sh — exercise the incognito flag, CLI, and PreToolUse guard
# against a throwaway vault (no touching the real brain).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON="$(cd "$HERE/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AGENTBRAIN_HOME="$TMP"
VAULT="$TMP/agentBrain"
mkdir -p "$VAULT/vault/sessions" "$VAULT/vault/learnings" "$VAULT/system"
echo '{}' >"$VAULT/brain.json"

fail=0
ok()   { printf '  ✓ %s\n' "$1"; }
bad()  { printf '  ✗ %s\n' "$1"; fail=1; }

# Build a PreToolUse payload for a given file path.
payload() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }

echo "1. is-incognito.sh reflects flag state"
if bash "$ADDON/is-incognito.sh"; then bad "should be OFF with no flag"; else ok "OFF when no flag"; fi
touch "$VAULT/vault/sessions/.incognito"
if bash "$ADDON/is-incognito.sh"; then ok "ON when flag present"; else bad "should be ON with flag"; fi
rm -f "$VAULT/vault/sessions/.incognito"

echo "2. CLI on/off/status"
bash "$ADDON/bin/incognito" on >/dev/null
[ -f "$VAULT/vault/sessions/.incognito" ] && ok "on creates flag" || bad "on did not create flag"
bash "$ADDON/bin/incognito" status | grep -q 'ON' && ok "status reports ON" || bad "status wrong"
bash "$ADDON/bin/incognito" off >/dev/null
[ -f "$VAULT/vault/sessions/.incognito" ] && bad "off left flag" || ok "off removes flag"

echo "3. PreToolUse guard"
# OFF: local write allowed
if payload "$VAULT/vault/learnings/x.md" | bash "$ADDON/claude-pretooluse-guard.sh"; then
	ok "OFF → local write allowed"; else bad "OFF should allow local write"; fi
# ON: local write blocked (exit 2)
bash "$ADDON/bin/incognito" on >/dev/null
if payload "$VAULT/vault/learnings/x.md" | bash "$ADDON/claude-pretooluse-guard.sh" 2>/dev/null; then
	bad "ON should block local write"; else ok "ON → local write blocked"; fi
# ON: system/ (code) write still allowed
if payload "$VAULT/system/foo.sh" | bash "$ADDON/claude-pretooluse-guard.sh"; then
	ok "ON → system/ code write allowed"; else bad "ON should allow system write"; fi
bash "$ADDON/bin/incognito" off >/dev/null

echo "4. session banner"
# OFF: no banner emitted
out="$(bash "$ADDON/session-banner.sh" 2>/dev/null)"
[ -z "$out" ] && ok "OFF → no banner" || bad "OFF should emit nothing (got: $out)"
# ON: banner emitted, and it still exits 0 (must never break a session)
bash "$ADDON/bin/incognito" on >/dev/null
out="$(bash "$ADDON/session-banner.sh" 2>/dev/null)"; rc=$?
echo "$out" | grep -q 'INCOGNITO' && ok "ON → banner injected" || bad "ON should emit a banner"
[ "$rc" -eq 0 ] && ok "hook exits 0 (never blocks a session)" || bad "hook must exit 0"
bash "$ADDON/bin/incognito" off >/dev/null

[ "$fail" -eq 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
