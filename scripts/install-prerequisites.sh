#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
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

# Version policy: install the LATEST bun/uv by default (like Node LTS) so a fresh
# install never ships stale tools; check-prerequisites.sh guards a minimum floor.
# Set AGENTBRAIN_BUN_VERSION / AGENTBRAIN_UV_VERSION to PIN an exact version for
# reproducible/CI installs.
BUN_VERSION="${AGENTBRAIN_BUN_VERSION:-}"
UV_VERSION="${AGENTBRAIN_UV_VERSION:-}"

export AGENTBRAIN_DIR PI_CONFIG_SOURCE

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
DIM='\033[2m'

# User-scoped tool paths: detect what is already installed (possibly earlier this
# same run) instead of re-offering it; rc edits are not sourced in this process.
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/_toolpaths.sh"
# bun's installer prints "Manually add ..." and does NOT persist PATH — do it
# idempotently, shell-aware (same pattern as the locale persist in the onboard
# skill): bash -> .bashrc, fish -> universal path, zsh/other -> .zshrc.
persist_bun_path() {
	[ -d "$HOME/.bun/bin" ] || return 0
	local rc=""
	case "${SHELL##*/}" in
		fish)
			if command -v fish >/dev/null 2>&1; then
				# shellcheck disable=SC2016  # $fish_user_paths is fish syntax — fish expands it, not this shell
				fish -c 'contains -- ~/.bun/bin $fish_user_paths; or fish_add_path -U ~/.bun/bin' >/dev/null 2>&1 || true
			fi
			return 0 ;;
		bash) rc="$HOME/.bashrc" ;;
		*)    rc="$HOME/.zshrc" ;;
	esac
	if ! grep -q 'BUN_INSTALL' "$rc" 2>/dev/null; then
		# shellcheck disable=SC2016  # literal $VARS wanted: the rc expands them at shell startup
		printf '\nexport BUN_INSTALL="$HOME/.bun"\nexport PATH="$BUN_INSTALL/bin:$PATH"\n' >> "$rc"
	fi
}
persist_bun_path

log() { printf '\n==> %s\n' "$*"; }
# Guided mode: one line of what+why before each step (installer first choice).
explain() { [ "${AGENTBRAIN_EXPLAIN:-}" = 1 ] && printf '%b\n' "${DIM:-\033[2m}   \xe2\x84\xb9 $*\033[0m" >&2 || true; }
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

# decide_tool <label> <detected: yes|no> <version-or-empty>
# Prints an honest detection line (to stderr), then asks. Echoes: install | update | keep | skip.
# Honors AGENTBRAIN_ASSUME_YES=1 and non-TTY (never hangs).
decide_tool() {
	local label="$1" det="$2" ver="${3:-}" ans
	# Numbered enum input (consistent with /onboard pick-lists): digits never
	# collide on shared initials (ask/auto!); unique letters accepted as bonus.
	if [ "$det" = yes ]; then
		printf '  %b\xe2\x9c\x93%b %-10s %bdetected%b%s\n' "${GREEN}" "${NC}" "$label" "${DIM}" "${NC}" "${ver:+ ($ver)}" >&2
		{ [ "${AGENTBRAIN_ASSUME_YES:-}" = 1 ] || [ ! -t 0 ]; } && { echo keep; return; }
		{
			printf '     1) keep    %b(default) present and fine — leave it%b\n' "${DIM}" "${NC}"
			printf '     2) update  %bfetch the latest version%b\n' "${DIM}" "${NC}"
			printf '     3) skip    %bskip this tool; the flow continues%b\n' "${DIM}" "${NC}"
		} >&2
		read -r -p "     choice [1]: " ans
		case "$ans" in 2|[Uu]*) echo update ;; 3|[Ss]*) echo skip ;; *) echo keep ;; esac
	else
		printf '  %b\xe2\x80\xa2%b %-10s %bnot found on this system%b\n' "${YELLOW}" "${NC}" "$label" "${DIM}" "${NC}" >&2
		[ "${AGENTBRAIN_ASSUME_YES:-}" = 1 ] && { echo install; return; }
		[ ! -t 0 ] && { echo skip; return; }
		{
			printf '     1) install %b(default) install it now%b\n' "${DIM}" "${NC}"
			printf '     2) skip    %bskip this tool; the flow continues%b\n' "${DIM}" "${NC}"
		} >&2
		read -r -p "     choice [1]: " ans
		case "$ans" in 2|[Ss]*) echo skip ;; *) echo install ;; esac
	fi
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
	explain "Node (via nvm): needed for Pi and agent CLIs (npm install). nvm keeps Node per-user, no sudo."
	# Prefer user-scoped nvm Node/npm over any system Node.
	load_nvm || true

	if command -v npm >/dev/null 2>&1; then
		printf '  %b\xe2\x9c\x93%b %-10s %bdetected%b (%s, npm %s)\n' "${GREEN}" "${NC}" "node" "${DIM}" "${NC}" "$(node -v 2>/dev/null)" "$(npm --version)"
		ok "Node/npm ready"
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

# Install Homebrew if missing (macOS). brew provides the Brewfile tools (jq,
# git-lfs, ffmpeg, …) and is otherwise absent on a clean Mac. Gated by
# _proceed_install (below): auto on AGENTBRAIN_ASSUME_YES=1, TTY-confirm
# otherwise, skipped in a bare non-TTY run so the flow never hangs.
ensure_homebrew() {
	[ "$(uname)" = "Darwin" ] || return 0
	explain "Homebrew: macOS package manager — provides jq, git-lfs, ffmpeg etc. from the Brewfile. Without brew those tools are skipped."
	local det=no ver=""
	command -v brew >/dev/null 2>&1 && { det=yes; ver="$(brew --version | head -1 | awk '{print $2}')"; }
	case "$(decide_tool Homebrew "$det" "$ver")" in
		keep) persist_brew_shellenv; ok "Homebrew kept (${ver})"; return ;;
		skip) warn "Homebrew skipped — brew-managed tools (jq, git-lfs, …) are skipped"; return ;;
	esac
	log "Installing Homebrew"
	if [ -t 0 ]; then
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	else
		NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	fi
	if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
	elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
	persist_brew_shellenv
	ok "Homebrew ready"
}

# Persist brew's shellenv for future shells (the brew installer only PRINTS the
# instruction). Idempotent; zsh -> ~/.zprofile, bash -> ~/.bash_profile (brew's
# own convention); other shells: brew's caveat covers it.
persist_brew_shellenv() {
	local bp="" rc=""
	if [ -x /opt/homebrew/bin/brew ]; then bp=/opt/homebrew/bin/brew
	elif [ -x /usr/local/bin/brew ]; then bp=/usr/local/bin/brew
	else return 0; fi
	case "${SHELL##*/}" in
		bash) rc="$HOME/.bash_profile" ;;
		fish) return 0 ;;
		*)    rc="$HOME/.zprofile" ;;
	esac
	if ! grep -q 'brew shellenv' "$rc" 2>/dev/null; then
		# shellcheck disable=SC2016  # the $( ) must stay literal — the rc evaluates it at shell startup
		printf '\neval "$(%s shellenv)"\n' "$bp" >> "$rc"
	fi
}

ensure_brew_bundle() {
	explain "Brewfile tools: jq (privacy-scan/event-bus), yt-dlp (youtube-digest), rg/fd (search) — per tool you see done vs missing."
	local brewfile="$PI_CONFIG_SOURCE/setup/Brewfile"
	[[ -f "$brewfile" ]] || return

	if ! command -v brew >/dev/null 2>&1; then
		warn "Homebrew not found — skipping brew bundle. Install from https://brew.sh then rerun."
		return
	fi

	log "Homebrew tools (from Brewfile)"
	local have nm ans any_missing=0
	have="$(brew list -1 2>/dev/null || true)"
	while IFS= read -r ln; do
		case "$ln" in brew\ *|cask\ *) ;; *) continue ;; esac
		nm="$(printf '%s' "$ln" | sed -E 's/^(brew|cask) +"?([^"#]+)"?.*/\2/; s/ +$//; s#.*/##')"
		[ -n "$nm" ] || continue
		if printf '%s\n' "$have" | grep -qx "$nm"; then
			printf '  %b\xe2\x9c\x93%b %s %balready installed%b\n' "${GREEN}" "${NC}" "$nm" "${DIM}" "${NC}"
		else
			printf '  %b\xe2\x80\xa2%b %s %bto install%b\n' "${YELLOW}" "${NC}" "$nm" "${DIM}" "${NC}"; any_missing=1
		fi
	done < "$brewfile"
	if [ "$any_missing" -eq 0 ]; then ok "All Homebrew tools already present"; return; fi
	ans=install
	if [ "${AGENTBRAIN_ASSUME_YES:-}" != 1 ]; then
		if [ -t 0 ]; then read -r -p "  Install the missing Homebrew tools? [Y/n] " a; case "$a" in [Nn]*) ans=skip ;; esac; else ans=skip; fi
	fi
	if [ "$ans" = install ]; then log "Installing missing Homebrew tools"; brew bundle --file="$brewfile" --no-upgrade; ok "Homebrew tools installed"; else warn "Skipped the missing Homebrew tools"; fi
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
	explain "bun: JS runtime for the MCP server (brain_search) and several addons."
	local det=no ver=""
	command -v bun >/dev/null 2>&1 && { det=yes; ver="$(bun --version 2>/dev/null)"; }
	case "$(decide_tool bun "$det" "$ver")" in
		keep) ok "bun kept (${ver})"; return ;;
		skip) warn "bun skipped — addons needing bun may not work"; return ;;
	esac
	if true; then
		# Latest by default; pin only when AGENTBRAIN_BUN_VERSION is set (the
		# official installer accepts a pinned release tag as its argument).
		if [ -n "$BUN_VERSION" ]; then
			log "Installing bun ${BUN_VERSION} (pinned)"; curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"
		else
			log "Installing bun (latest)"; curl -fsSL https://bun.sh/install | bash
		fi
		export BUN_INSTALL="$HOME/.bun"
		case ":$PATH:" in *":$BUN_INSTALL/bin:"*) ;; *) PATH="$BUN_INSTALL/bin:$PATH" ;; esac
		persist_bun_path
		ok "bun installed (PATH loaded for this run + persisted for your shell)"
	fi
}

# ── uv ────────────────────────────────────────────────────────────────────────

ensure_uv() {
	explain "uv: fast Python runner — only needed for optional addons (graphify); skipping is fine."
	local det=no ver=""
	command -v uv >/dev/null 2>&1 && { det=yes; ver="$(uv --version 2>/dev/null | awk '{print $2}')"; }
	case "$(decide_tool uv "$det" "$ver")" in
		keep) ok "uv kept (${ver})"; return ;;
		skip) warn "uv skipped — addons needing uv may not work"; return ;;
	esac
	if true; then
		# Latest by default; pin only when AGENTBRAIN_UV_VERSION is set (astral.sh
		# serves a versioned installer path for reproducible/CI installs).
		if [ -n "$UV_VERSION" ]; then
			log "Installing uv ${UV_VERSION} (pinned)"; curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh
		else
			log "Installing uv (latest)"; curl -LsSf https://astral.sh/uv/install.sh | sh
		fi
		case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
		ok "uv installed (PATH loaded for this run)"
	fi
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
	echo "========================================================================"
	echo "Developer tools"
	echo "========================================================================"
	ensure_homebrew
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
