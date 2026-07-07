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

# Pinned installer versions (consistent with the nvm pin below): piping a
# moving "latest" installer into a shell is not reproducible. Bump deliberately;
# override per-machine via the env vars when needed.
BUN_VERSION="${AGENTBRAIN_BUN_VERSION:-1.2.19}"
UV_VERSION="${AGENTBRAIN_UV_VERSION:-0.7.19}"

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

# ── install decision ───────────────────────────────────────────────────────────

# Decide whether to install a prereq. Testable: no curl, no read on the no-path.
# Proceed when AGENTBRAIN_ASSUME_YES=1, or on a TTY after a yes. Never in a bare
# non-TTY run (caller can re-run with --yes / AGENTBRAIN_ASSUME_YES=1).
_proceed_install() {
	[ "${AGENTBRAIN_ASSUME_YES:-}" = "1" ] && return 0
	if [ -t 0 ]; then
		local ans
		read -r -p "Install $1 (fast runtime)? [y/N] " ans
		case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
	fi
	return 1
}

# ── bun ───────────────────────────────────────────────────────────────────────

ensure_bun() {
	if command -v bun >/dev/null 2>&1; then ok "bun $(bun --version) available"; return; fi
	if _proceed_install bun; then
		# The official installer accepts a pinned release tag as its argument.
		log "Installing bun ${BUN_VERSION}"; curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"; ok "bun installed"
	else
		warn "bun not installed (non-interactive, no --yes) — addons needing bun are skipped"
	fi
}

# ── uv ────────────────────────────────────────────────────────────────────────

ensure_uv() {
	if command -v uv >/dev/null 2>&1; then ok "uv $(uv --version) available"; return; fi
	if _proceed_install uv; then
		# astral.sh serves a versioned installer path — pin instead of "latest".
		log "Installing uv ${UV_VERSION}"; curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh; ok "uv installed"
	else
		warn "uv not installed (non-interactive, no --yes) — addons needing uv are skipped"
	fi
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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
