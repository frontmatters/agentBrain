#!/usr/bin/env bash
# bootstrap-macos.sh — Bootstrap agentBrain + developer tools + Pi on macOS.
# Orchestrates the full setup in four steps:
#   1. Developer tools  (nvm, Node LTS, Homebrew, bun, uv)
#   2. agentBrain       (local/ structure, agent pointers for all clients)
#   3. Pi               (install Pi, extensions, skills, tsconfig, credentials)
#   4. Validation       (doctor health checks)
#
# Idempotent — safe to re-run after a Pi update or on a new machine.
# macOS only. For other platforms run: ./setup.sh

set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPTS="$AGENTBRAIN_DIR/scripts"

export AGENTBRAIN_DIR

log() { printf '\n==> %s\n' "$*"; }

require_macos() {
	if [[ "$(uname -s)" != "Darwin" ]]; then
		echo "This bootstrap targets macOS only." >&2
		echo "For other platforms run: ./setup.sh" >&2
		exit 1
	fi
}

main() {
	require_macos

	echo "========================================================================"
	echo "agentBrain bootstrap — macOS"
	echo "Location: ${AGENTBRAIN_DIR}"
	echo "========================================================================"

	log "Step 1/4 — Developer tools (nvm, Node LTS, Homebrew, bun, uv)"
	bash "$SCRIPTS/install-prerequisites.sh"

	log "Step 2/4 — agentBrain (local structure + agent pointers)"
	bash "$SCRIPTS/setup.sh"

	log "Step 3/4 — Pi (install + extensions, skills, tsconfig)"
	bash "$SCRIPTS/configure-pi.sh"

	log "Step 4/4 — Validation"
	bash "$SCRIPTS/doctor.sh" --summary

	echo ""
	echo "========================================================================"
	echo "Bootstrap complete."
	echo "Restart Pi or run /reload in an existing Pi session."
	echo "========================================================================"
}

main "$@"
