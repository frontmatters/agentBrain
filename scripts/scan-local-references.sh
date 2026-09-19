#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# scan-local-references.sh — where does `local/` still live?
#
# The vault moved from `local/` to `vault/`. A leftover reference is silent: a missing file
# produces no error, only knowledge that never arrives (six of them sat in the Copilot
# pointer block for weeks, found 2026-09-16). This sweeps every checkout under the factory
# and reports what still says `local`, split by whether it is a real path or just the word.
#
# Read-only. It changes nothing; it tells you what to change.
#
#   bash scripts/checks/scan-local-references.sh            # summary per checkout
#   bash scripts/checks/scan-local-references.sh --detail   # every hit, with file and line
set -uo pipefail

FACTORY="${AGENTBRAIN_FACTORY:-$HOME/Developer/agentBrain-factory}"
DETAIL=0; [ "${1:-}" = "--detail" ] && DETAIL=1

# A path reference is the one that breaks. The bare word appears in prose all the time
# ("local time", "locally"), so those are counted separately and never reported as a fault.
PATH_PAT='(\$\{?BRAIN[A-Z_]*\}?/|agentBrain/|\.\./|["`'"'"' (])local/'
SKIP='/(\.git|node_modules|dist|\.trash|quarantine|graphify-out|\.venv)/'

# Split by consequence, not by count. A reference under scripts/ or system/ is EXECUTED: a
# dead path there costs a command or a body of knowledge. A reference in a changelog, a
# session log or an archived note is RECORDED: it describes the layout of the time, and
# rewriting it would falsify the record. Only the first list is work.
uitgevoerd=0; vastgelegd=0
for checkout in "$FACTORY"/*/; do
  [ -d "$checkout" ] || continue
  naam="$(basename "$checkout")"
  u=0; v=0
  while IFS= read -r regel; do
    printf '%s\n' "$regel" | grep -qE "$SKIP" && continue
    printf '%s\n' "$regel" | grep -qE "$PATH_PAT" || continue
    bestand="${regel%%:*}"
    rel="${bestand#"$checkout"}"
    case "$rel" in
      CHANGELOG*|*/CHANGELOG*|*/archive/*|*/sessions/*|*/journal/*|*/.trash/*|*/releases/*)
        v=$((v + 1)) ;;
      scripts/*|system/*|templates/*|*.sh|*.mjs|*.py|*.json|*.toml|*.yaml|*.yml)
        u=$((u + 1)); [ "$DETAIL" = 1 ] && printf '  %s\n' "${regel#"$FACTORY"/}" ;;
      *) v=$((v + 1)) ;;
    esac
  done < <(grep -rIn --exclude-dir=.git --exclude-dir=node_modules -E 'local' "$checkout" 2>/dev/null || true)
  [ $((u + v)) -eq 0 ] && continue
  printf '%-28s UITGEVOERD: %-5s vastgelegd: %s\n' "$naam" "$u" "$v"
  uitgevoerd=$((uitgevoerd + u)); vastgelegd=$((vastgelegd + v))
done

echo
echo "te corrigeren (uitgevoerd): ${uitgevoerd}"
echo "geschiedenis (laat staan):  ${vastgelegd}"
[ "$DETAIL" = 1 ] || echo "draai met --detail voor bestand en regel van de eerste groep"
