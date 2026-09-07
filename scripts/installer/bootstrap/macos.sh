#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
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

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SCRIPTS="$AGENTBRAIN_DIR/scripts"
# shellcheck source=scripts/installer/flow.sh
	. "$SCRIPTS/installer/flow.sh"

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

	local BOOT="bootstrap-macos"

	log "Step 1/2 — Developer tools (cascaded: brew/apt/binary via capability offers)"
	flow_begin "$BOOT.step1-tools"
	rc=0
	bash "$SCRIPTS/tools/install-prerequisites.sh" || rc=$?
	flow_end "$BOOT.step1-tools" "$rc"
	[ "$rc" -eq 0 ] || exit "$rc"

	log "Step 2/2 — agentBrain brain (structure, pointers, Pi configuration, doctor validation)"
	# Pi configuration + doctor validation live INSIDE setup.sh (single owner:
	# ronde 7) — no SKIP_PI dance, no duplicate doctor.
	flow_begin "$BOOT.step2-brain"
	AGENTBRAIN_BOOTSTRAP=1 bash "$SCRIPTS/setup/setup.sh"
	flow_end "$BOOT.step2-brain" $?

	echo ""
	echo "========================================================================"
	echo "Bootstrap complete."
	echo ""
	echo "IMPORTANT — this run added tools to your PATH via your shell rc."
	echo "Your CURRENT terminal predates those lines, so first run:"
	echo ""
	echo "    exec zsh -l     (or simply open a new terminal window)"
	echo ""
	echo "Then start onboarding:"
	echo ""
	echo "    pi              (first time: /login to connect a model provider,"
	echo "                     then: /onboard to personalize your brain)"
	echo "========================================================================"
}

main "$@"
