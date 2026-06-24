#!/usr/bin/env bash
# Claude Code SessionStart hook: run brain-update --session so the configured
# auto_update mode (notify/auto/off) acts at the start of a session. Its stdout
# is added to the session context, so a 'notify' message surfaces to you.
#
# Fail-safe by construction: must NEVER block or fail a session. Finds the first
# available brain-update.sh (live vault first, then this script's dir), runs it,
# and swallows every error. Exits 0 no matter what.
set +e

for cand in \
  "$HOME/agentBrain/scripts/brain-update.sh" \
  "$(dirname "$0")/brain-update.sh"; do
  if [ -f "$cand" ]; then
    bash "$cand" --session 2>/dev/null || true
    break
  fi
done

exit 0
