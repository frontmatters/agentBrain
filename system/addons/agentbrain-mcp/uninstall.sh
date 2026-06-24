#!/usr/bin/env bash
# Uninstall the agentBrain MCP server. True inverse of install.sh: unregisters the
# server from every detected MCP client via the same register.ts path install uses,
# so this is a genuine inverse rather than a divergent re-implementation.
# Idempotent: running it twice (or with nothing registered) is a no-op that exits 0.
#
#   bash uninstall.sh            # unregister from detected MCP clients (keep node_modules)
#   bash uninstall.sh --purge    # also remove the addon's node_modules/
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

# Reuse install.sh's --uninstall path: identical de-registration logic, single
# source of truth for which clients are touched and how.
bash "$HERE/install.sh" --uninstall

if [ "$PURGE" = "1" ]; then
  if [ -d "$HERE/node_modules" ]; then
    rm -rf "$HERE/node_modules"
    echo "Purged JS deps ($HERE/node_modules)"
  fi
else
  echo "Kept JS deps in node_modules (use --purge to remove)"
fi
