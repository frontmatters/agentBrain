#!/usr/bin/env bash
# Tests voor ask_or_forward (Tier 0/1). Draait non-TTY (geen terminal in de
# runner), dus de niet-interactieve paden zijn de default.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT_DIR" || exit 1
pass=0; fail=0; fails=()
assert(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$1: got '$2' want '$3'"); fi; }

# shellcheck disable=SC1091
source scripts/lib/ask_or_forward.sh

# Tier 0: env wint
export AGENTBRAIN_LOCALE="nl"
assert "tier0 env" "$(ask_or_forward locale 'Welke taal?' en optional 2>/dev/null)" "nl"
unset AGENTBRAIN_LOCALE

# Tier 1: non-essentieel, geen env -> default + skip-note op stderr
out="$(ask_or_forward locale 'Welke taal?' en optional 2>/tmp/aof.err)"
assert "tier1 default" "$out" "en"
assert "tier1 note"    "$(grep -c 'SKIP locale' /tmp/aof.err)" "1"

# Tier 2-hook: essentieel, geen antwoord -> non-zero return (niet stil beslist)
ask_or_forward db_url 'DB URL?' '' essential >/dev/null 2>&1
assert "tier2 return" "$?" "2"

rm -f /tmp/aof.err

# --- _proceed_install: non-TTY respecteert AGENTBRAIN_ASSUME_YES ---
# Note: sourcing install-prerequisites.sh activates set -e in this shell.
# Use || ret=$? to capture non-zero exits without aborting.
# shellcheck disable=SC1091
source scripts/install-prerequisites.sh >/dev/null 2>&1 || true
export AGENTBRAIN_ASSUME_YES=1
_proceed_install bun; assert "proceed assume-yes" "$?" "0"
unset AGENTBRAIN_ASSUME_YES
ret=0; _proceed_install bun || ret=$?; assert "proceed non-tty-no-yes" "$ret" "1"

echo "pass=$pass fail=$fail"; for f in "${fails[@]:-}"; do [ -n "$f" ] && echo "FAIL: $f"; done
[ "$fail" -eq 0 ]
