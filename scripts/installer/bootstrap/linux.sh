#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# bootstrap-linux.sh — Bootstrap agentBrain + developer tools + Pi on Linux
# (WSL2 included; de flavor wordt in de header geprint). Symmetrische tweeling
# van bootstrap-macos.sh: zelfde 4-stappen-contract. Per stap geldt de regel:
# werkt de stap op alle OS-en -> hoofdroute; zo niet -> OS-aftakking die naar
# de hoofdroute terugkeert.
# Orchestrates the full setup in four steps:
#   1. Developer tools  (nvm, Node LTS, Homebrew, bun, uv)
#   2. agentBrain       (local/ structure, agent pointers for all clients)
#   3. Pi               (install Pi, extensions, skills, tsconfig, credentials)
#   4. Validation       (doctor health checks)
#
# Idempotent — safe to re-run after a Pi update or on a new machine.
# Linux only (WSL2 included). macOS: scripts/bootstrap-macos.sh

set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SCRIPTS="$AGENTBRAIN_DIR/scripts"
# shellcheck source=scripts/installer/flow.sh
	. "$SCRIPTS/installer/flow.sh"

export AGENTBRAIN_DIR

log() { printf '\n==> %s\n' "$*"; }

require_linux() {
	. "$SCRIPTS/lib/platform.sh"
	if [ "$(platform_os)" != "linux" ]; then
		echo "This bootstrap targets Linux (WSL2 included; mac: bootstrap-macos.sh)." >&2
		exit 1
	fi
}

main() {
	require_linux

	# Visible WSL version check (user request 2026-09): show the detected
	# generation, and refuse to run a broken install on WSL 1 — nvm/node/pnpm
	# do not work there, which previously surfaced as cryptic mid-step errors.
	local wsl_ver="" flavor_label
	flavor_label="$(platform_flavor)"
	if [ "$flavor_label" = wsl ]; then
		wsl_ver="$(platform_wsl_version)"
		case "$wsl_ver" in
			2) flavor_label="wsl — WSL 2 ✓" ;;
			1) flavor_label="wsl — WSL 1 ✗ (not supported)" ;;
			*) flavor_label="wsl — WSL version unknown" ;;
		esac
	fi

	echo "========================================================================"
	echo "agentBrain bootstrap — Linux (flavor: $flavor_label)"
	echo "Location: ${AGENTBRAIN_DIR}"
	echo "========================================================================"

	if [ "$wsl_ver" = "1" ]; then
		echo ""
		echo "✗ WSL 1 detected — agentBrain requires WSL 2."
		echo "  nvm, node and pnpm do not function on WSL 1; the tool step would fail mid-way."
		echo "  Remediation — from Windows PowerShell:"
		echo "      wsl -l -v                          # confirm: VERSION column says 1"
		echo "      wsl --set-version <distro> 2       # convert this distro (takes a while)"
		echo "      wsl --set-default-version 2        # future distros install as 2"
		echo "  Then re-run this installer."
		exit 1
	fi

	local BOOT="bootstrap-linux"
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
