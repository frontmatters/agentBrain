#!/usr/bin/env bash
# install.sh — install/uninstall the agentBrain MCP server into detected MCP clients.
# Idempotent + uninstall-symmetric. Registers ONLY into clients that are detected
# (their config dir exists), writing a config path verified against the client's docs.
set -euo pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRAIN_ALIAS="${BRAIN_ALIAS:-$HOME/agentBrain}"
export BRAIN_ALIAS

if [ "${1:-}" = "--uninstall" ]; then
	bun "$ADDON_DIR/src/register.ts" --uninstall
	echo "agentBrain MCP unregistered."
	exit 0
fi

echo "Installing JS deps…"
(cd "$ADDON_DIR" && bun install)
bun "$ADDON_DIR/src/register.ts"
echo "agentBrain MCP registered. Restart Cursor/Windsurf to pick it up."
