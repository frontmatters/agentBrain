#!/usr/bin/env bash
# install-prerequisites.sh — Install developer tools for agentBrain on macOS.
# Installs: nvm, Node LTS (via nvm), Homebrew dependencies (Brewfile).
# These tools are useful regardless of which AI client you use.
# Pi itself is installed by scripts/configure-pi.sh.
# Idempotent — safe to re-run.
#
# Called by: scripts/bootstrap-macos.sh
# Can also be run standalone to (re)install tools after a machine reset.

set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PI_CONFIG_SOURCE="${PI_CONFIG_SOURCE:-$AGENTBRAIN_DIR/system/pi-config}"

export AGENTBRAIN_DIR PI_CONFIG_SOURCE

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\n%bWARN%b: %s\n' "${YELLOW}" "${NC}" "$*" >&2; }
ok() { printf '%b%s%b\n' "${GREEN}" "$*" "${NC}"; }

# ── nvm / Node LTS ────────────────────────────────────────────────────────────

load_nvm() {
	export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
	if [[ -s "$NVM_DIR/nvm.sh" ]]; then
		# shellcheck disable=SC1091
		. "$NVM_DIR/nvm.sh"
		return 0
	fi
	return 1
}

install_nvm() {
	if [[ "${AGENTBRAIN_INSTALL_NVM:-}" == "1" ]]; then
		log "Installing nvm"
		curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
		load_nvm || return 1
		return 0
	fi

	if [[ -t 0 ]]; then
		read -r -p "npm not found. Install nvm-managed Node LTS now? [y/N] " answer
		case "$answer" in
		[Yy]*)
			log "Installing nvm"
			curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
			load_nvm || return 1
			return 0
			;;
		esac
	fi

	return 1
}

ensure_node_package_manager() {
	# Prefer user-scoped nvm Node/npm over any system Node.
	load_nvm || true

	if command -v npm >/dev/null 2>&1; then
		ok "npm $(npm --version) available"
		return
	fi

	if ! command -v nvm >/dev/null 2>&1; then
		install_nvm || {
			warn "npm unavailable. Install nvm, then: nvm install --lts && nvm use --lts"
			exit 1
		}
	fi

	log "Installing Node LTS via nvm"
	nvm install --lts
	nvm use --lts

	if ! command -v npm >/dev/null 2>&1; then
		warn "npm still unavailable after nvm setup. Open a new shell or source ~/.nvm/nvm.sh, then rerun."
		exit 1
	fi

	ok "npm $(npm --version) available (nvm)"
}

# ── Homebrew ──────────────────────────────────────────────────────────────────

ensure_brew_bundle() {
	local brewfile="$PI_CONFIG_SOURCE/setup/Brewfile"
	[[ -f "$brewfile" ]] || return

	if ! command -v brew >/dev/null 2>&1; then
		warn "Homebrew not found — skipping brew bundle. Install from https://brew.sh then rerun."
		return
	fi

	log "Installing Homebrew dependencies"
	brew bundle --file="$brewfile" --no-upgrade
	ok "Homebrew dependencies installed"
}

# ── bun ───────────────────────────────────────────────────────────────────────

ensure_bun() {
	if command -v bun >/dev/null 2>&1; then
		ok "bun $(bun --version) available"
		return
	fi

	if [[ -t 0 ]]; then
		read -r -p "Install bun (fast JS runtime, used by opensrc and other tools)? [y/N] " answer
		case "$answer" in
		[Yy]*) ;;
		*) return ;;
		esac
	else
		# non-interactive: skip
		return
	fi

	log "Installing bun"
	curl -fsSL https://bun.sh/install | bash
	ok "bun installed"
}

# ── uv ────────────────────────────────────────────────────────────────────────

ensure_uv() {
	if command -v uv >/dev/null 2>&1; then
		ok "uv $(uv --version) available"
		return
	fi

	if [[ -t 0 ]]; then
		read -r -p "Install uv (fast Python package manager, used by graphify and other tools)? [y/N] " answer
		case "$answer" in
		[Yy]*) ;;
		*) return ;;
		esac
	else
		# non-interactive: skip
		return
	fi

	log "Installing uv"
	curl -LsSf https://astral.sh/uv/install.sh | sh
	ok "uv installed"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
	echo "========================================================================"
	echo "Developer tools"
	echo "========================================================================"
	ensure_node_package_manager
	ensure_brew_bundle
	ensure_bun
	ensure_uv
	echo ""
	ok "Developer tools done"
}

main "$@"
