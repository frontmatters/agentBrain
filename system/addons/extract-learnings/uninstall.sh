#!/usr/bin/env bash
# Uninstall the extract-learnings adapters. True inverse of install.sh: removes the
# Claude PreCompact hook from ~/.claude/settings.json via the same python patching.
# Idempotent: running it twice (or with no hook installed) is a no-op that exits 0.
#
#   bash uninstall.sh            # remove the PreCompact hook entry (keep settings.json)
#   bash uninstall.sh --purge    # also remove extracted learnings in local/learnings/extracted
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

# Reuse install.sh's --uninstall path: identical match-by-script-identity python
# removal, so this is a genuine inverse rather than a divergent re-implementation.
bash "$HERE/install.sh" --uninstall

if [ "$PURGE" = "1" ]; then
  BRAIN="$(cd "$HERE/../../.." && pwd)"
  EXTRACTED="$BRAIN/local/learnings/extracted"
  if [ -d "$EXTRACTED" ]; then
    rm -rf "$EXTRACTED"
    echo "Purged extracted learnings ($EXTRACTED)"
  fi
else
  echo "Kept extracted learnings in local/learnings/extracted (use --purge to remove)"
fi
