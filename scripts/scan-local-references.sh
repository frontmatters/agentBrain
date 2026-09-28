#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# scan-local-references.sh — where does `local/` still live?
#
# The vault moved from `local/` to `vault/`. A leftover reference is silent: a missing file
# produces no error, only knowledge that never arrives. This sweeps every checkout under a
# parent directory and reports what still says `local`, split by whether it is a real path
# or just the word.
#
# Read-only. It changes nothing; it tells you what to change.
#
#   bash scripts/scan-local-references.sh [--detail] [DIR]
#     --detail   every hit, with file and line (default: a summary per checkout)
#     DIR        the directory holding the checkouts; default $AGENTBRAIN_FACTORY,
#                else the parent of this checkout
set -uo pipefail

DETAIL=0; [ "${1:-}" = "--detail" ] && { DETAIL=1; shift; }
FACTORY="${1:-${AGENTBRAIN_FACTORY:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"

# A path reference is the one that breaks. The bare word appears in prose all the time
# ("local time", "locally"), so those are counted separately and never reported as a fault.
PATH_PAT='(\$\{?BRAIN[A-Z_]*\}?/|agentBrain/|\.\./|["`'"'"' (])local/'
SKIP='/(\.git|node_modules|dist|\.trash|quarantine|graphify-out|\.venv)/'

# Split by consequence, not by count. A reference under scripts/ or system/ is EXECUTED: a
# dead path there costs a command or a body of knowledge. A reference in a changelog, a
# session log or an archived note is RECORDED: it describes the layout of the time, and
# rewriting it would falsify the record. Only the first list is work.
executed=0; recorded=0
for checkout in "$FACTORY"/*/; do
  [ -d "$checkout" ] || continue
  name="$(basename "$checkout")"
  u=0; v=0
  while IFS= read -r line; do
    printf '%s\n' "$line" | grep -qE "$SKIP" && continue
    printf '%s\n' "$line" | grep -qE "$PATH_PAT" || continue
    file="${line%%:*}"
    rel="${file#"$checkout"}"
    case "$rel" in
      CHANGELOG*|*/CHANGELOG*|*/archive/*|*/sessions/*|*/journal/*|*/.trash/*|*/releases/*)
        v=$((v + 1)) ;;
      scripts/*|system/*|templates/*|*.sh|*.mjs|*.py|*.json|*.toml|*.yaml|*.yml)
        u=$((u + 1)); [ "$DETAIL" = 1 ] && printf '  %s\n' "${line#"$FACTORY"/}" ;;
      *) v=$((v + 1)) ;;
    esac
  done < <(grep -rIn --exclude-dir=.git --exclude-dir=node_modules -E 'local' "$checkout" 2>/dev/null || true)
  [ $((u + v)) -eq 0 ] && continue
  printf '%-28s EXECUTED: %-5s recorded: %s\n' "$name" "$u" "$v"
  executed=$((executed + u)); recorded=$((recorded + v))
done

echo
echo "to fix (executed):          ${executed}"
echo "history (leave as is):      ${recorded}"
[ "$DETAIL" = 1 ] || echo "run with --detail for the file and line of each hit in the first group"
