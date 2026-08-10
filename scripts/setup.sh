#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# setup.sh — Initialize agentBrain in-place and install agent pointers.
# A modular orchestrator: each step is a self-contained subscript that also runs standalone.
# Preconditions first (dependency check, install base AGENTBRAIN_HOME, active-brain alias,
# brain CLI on PATH), then the labelled steps:
#   1. Structure
#   2. Brain config (must precede templates — UUID5 ids depend on brain.json namespace)
#   3. Templates and preferences
#   4. Agent CLIs (optional, opt-in — install agents you don't have yet; never auto-installs)
#   5. Connecting your AI tools (pointers + skills + behaviors for detected agents)
#   6. Git hooks
#   7. Health check
# Followed by an optional Pi integration step when Pi is detected.
# Run once after cloning. Safe to re-run (idempotent).
# Important: this script never moves or renames the agentBrain checkout.

set -euo pipefail

# Ensure Homebrew is in PATH
if [ "$(uname)" = "Darwin" ] && [ -x /opt/homebrew/bin/brew ]; then
	eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)"
fi

VAULT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="${VAULT}/scripts"

# ── Help ─────────────────────────────────────
for _arg in "$@"; do
	case "$_arg" in
	-h | --help)
		cat <<'EOF'
agentBrain setup — install agent connectors for this brain (idempotent).

Usage:
  ./setup.sh                 Install/refresh connectors for every detected AI tool.
  ./setup.sh --yes           Non-interactive (auto-confirm ALL prompts, including the
                             sudo apt-get dependency install on Linux; for CI/agents).
  ./setup.sh --home=PATH     Install base for tool configs (default: $HOME). Advanced —
                             for sandbox/CI/alternate profiles; the agent CLIs read fixed
                             $HOME paths, so a non-$HOME base only suits those cases.
  ./setup.sh --move-to PATH  Relocate the agentBrain checkout (delegates to move-agentbrain.sh).
  -h, --help                 Show this help.

  ./setup.sh --vault=PATH    Point this checkout's private local/ at a shared central
                             vault (so multiple checkouts share one knowledge store).
                             Default: a real, unshared local/ dir in the checkout.

Environment:
  AGENTBRAIN_HOME=PATH       Same as --home= (flag wins if both are given).
  AGENTBRAIN_VAULT=PATH      Same as --vault= (shared private vault for local/).
  AGENTBRAIN_SKIP_PI=1       Skip the optional Pi configuration step (headless/CI).
EOF
		exit 0
		;;
	esac
done

# ── Handle --move-to ────────────────────────
if [[ "${1:-}" == "--move-to" ]]; then
	if [[ -z "${2:-}" ]]; then
		echo "ERROR: --move-to requires a target path" >&2
		echo "Usage: scripts/setup.sh --move-to /new/path/agentBrain" >&2
		exit 1
	fi
	exec "${SCRIPTS}/move-agentbrain.sh" "$2"
fi

export VAULT

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Non-interactive mode ─────────────────────
# --yes/-y/--non-interactive or AGENTBRAIN_ASSUME_YES=1 auto-confirms prompts (full
# unattended setup — e.g. an AI agent that already has the user's consent). Without it, a
# non-TTY run SKIPS consequential prompts with an agent-readable note, so the agent can ask
# the user and re-run with --yes (rather than the script hanging or silently deciding).
ASSUME_YES=false
[ "${AGENTBRAIN_ASSUME_YES:-}" = "1" ] && ASSUME_YES=true
for _arg in "$@"; do
	case "$_arg" in
	--yes | -y | --non-interactive) ASSUME_YES=true ;;
	esac
done

# confirm <prompt> [<skip-note>] [<default Y|N>]
confirm() {
	local prompt="$1" note="${2:-}" default="${3:-N}"
	if [ "$ASSUME_YES" = true ]; then
		return 0
	fi
	# Prompt on the terminal even when stdin is a pipe (curl | bash): /dev/tty.
	local tty_src=""
	if [ -t 0 ]; then tty_src=/dev/stdin
	elif [ -e /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; then tty_src=/dev/tty; fi
	if [ -n "$tty_src" ]; then
		local hint="[y/N]"
		[ "$default" = "Y" ] && hint="[Y/n]"
		# Re-ask on anything that isn't y/n/Enter — a stray arrow key (ESC [ B)
		# must never count as an answer. Drain the escape tail before re-asking.
		while true; do
			read -p "$prompt $hint " -n 1 -r < "$tty_src"
			echo
			case "$REPLY" in
				""|[YyNn]) break ;;
				*) read -rs -t 0.05 -n 16 _ < "$tty_src" || true ;;
			esac
		done
		if [ "$default" = "Y" ]; then [[ ! $REPLY =~ ^[Nn]$ ]]; else [[ $REPLY =~ ^[Yy]$ ]]; fi
		return
	fi
	echo "[non-interactive] skipped: $prompt"
	[ -n "$note" ] && echo "  -> $note"
	echo "  -> re-run with --yes (or AGENTBRAIN_ASSUME_YES=1) to proceed, or ask the user."
	return 1
}

# Detect platform
PLATFORM="unknown"
if [ "$(uname)" = "Darwin" ]; then
	PLATFORM="macOS"
elif [ -n "${WSL_DISTRO_NAME:-}" ]; then
	PLATFORM="WSL (${WSL_DISTRO_NAME})"
elif [ "$(uname)" = "Linux" ]; then
	PLATFORM="Linux"
fi

# ── Install base ─────────────────────────────
# Where each AI tool's config lives (~/.claude, ~/.gemini, ~/.pi, …). Defaults to $HOME
# silently — that is what the agent CLIs actually read, so it is the right answer for
# normal installs and not worth a prompt. Override only for sandbox/test/CI/alternate
# profiles, via --home=PATH or the AGENTBRAIN_HOME env var. (The install validation sets
# AGENTBRAIN_HOME to a throwaway dir, which is exactly how it stays isolated.)
for _arg in "$@"; do
	case "$_arg" in
	--home=*) AGENTBRAIN_HOME="${_arg#--home=}" ;;
	esac
done
AGENTBRAIN_HOME="${AGENTBRAIN_HOME:-$HOME}"
AGENTBRAIN_HOME="${AGENTBRAIN_HOME/#\~/$HOME}" # expand a leading ~
mkdir -p "$AGENTBRAIN_HOME"
export AGENTBRAIN_HOME

# ── Shared private vault (optional) ──────────────────────────
# Where the private local/ layer lives. Unset = a real local/ dir in the checkout
# (the default). Set = a symlink into a shared central vault, so multiple checkouts
# (e.g. live + dev) share one knowledge store. Resolved by setup-local-vault.sh below.
for _arg in "$@"; do
	case "$_arg" in
	--vault=*) AGENTBRAIN_VAULT="${_arg#--vault=}" ;;
	esac
done
export AGENTBRAIN_VAULT="${AGENTBRAIN_VAULT:-}"
# Propagate the confirm-default to subscripts (separate processes can't see the function).
[ "$ASSUME_YES" = true ] && export AGENTBRAIN_ASSUME_YES=1

# ── Active-brain alias ───────────────────────
# Agents are pointed at this stable, switchable symlink (default ~/agentBrain),
# so `brain use dev|live` later flips ONE link instead of rewriting every pointer.
# Created pointing at the checkout setup runs from; only if absent, so a deliberate
# `brain use` choice is never clobbered.
BRAIN_ALIAS="${AGENTBRAIN_HOME}/agentBrain"
if [ -L "$BRAIN_ALIAS" ] && [ ! -e "$BRAIN_ALIAS" ]; then
	# Dangling alias: every pointer written below would route through a broken
	# link. Repair after confirmation, or stop with a clear explanation (same
	# policy as the dangling local/ check in setup-local-vault.sh).
	echo -e "${YELLOW}!${NC} ${BRAIN_ALIAS} is a DANGLING symlink -> $(readlink "$BRAIN_ALIAS") — agents would point into the void."
	if confirm "Re-point it at this checkout (${VAULT})?" "Restore the old target, or re-run and confirm to re-link." Y; then
		ln -sfn "$VAULT" "$BRAIN_ALIAS"
		echo -e "${GREEN}Relinked${NC} ${BRAIN_ALIAS} -> ${VAULT}"
	else
		echo "  Restore the target or remove the link, then re-run setup."
		exit 1
	fi
elif [ ! -e "$BRAIN_ALIAS" ]; then
	ln -sfn "$VAULT" "$BRAIN_ALIAS"
fi
export BRAIN_ALIAS

# Put the `brain` CLI (switch dev|live, status) on PATH — best-effort.
# Only for real installs: in sandbox mode (AGENTBRAIN_HOME != $HOME) an
# `ln -sfn` here would hijack the user's existing `brain` command and point
# it at the throwaway checkout.
BRAIN_BIN_DIR=""
if [ "$AGENTBRAIN_HOME" = "$HOME" ]; then
	[ -d "$HOME/bin" ] && BRAIN_BIN_DIR="$HOME/bin"
	[ -z "$BRAIN_BIN_DIR" ] && [ -d "$HOME/.local/bin" ] && BRAIN_BIN_DIR="$HOME/.local/bin"
fi
if [ -n "$BRAIN_BIN_DIR" ]; then
	# Two names, one CLI: `brain` (daily driver) + `agentbrain` (discoverable alias).
	for _cli_name in brain agentbrain; do
		BRAIN_BIN="$BRAIN_BIN_DIR/$_cli_name"
		# Never hijack an unrelated command: only (re)link when the target is
		# absent or already an agentBrain link (a symlink to some checkout's brain.sh).
		if [ -e "$BRAIN_BIN" ] || [ -L "$BRAIN_BIN" ]; then
			if [ -L "$BRAIN_BIN" ] && [ "$(basename "$(readlink "$BRAIN_BIN")")" = "brain.sh" ]; then
				ln -sfn "$VAULT/scripts/brain.sh" "$BRAIN_BIN"
			else
				echo "Note: ${BRAIN_BIN} exists and is not an agentBrain link — left untouched."
				echo "  Symlink $VAULT/scripts/brain.sh onto your PATH yourself to use the '$_cli_name' command."
			fi
		else
			ln -sfn "$VAULT/scripts/brain.sh" "$BRAIN_BIN"
		fi
	done
else
	echo "Note: symlink $VAULT/scripts/brain.sh onto your PATH to use the 'brain' command."
fi

# The dir we just linked `brain` into must be on the INTERACTIVE shell's PATH too
# (~/.local/bin is not in macOS' default PATH; uv's rc line used to mask this).
# Idempotent, shell-aware — same pattern as the bun/brew persists.
if [ -n "$BRAIN_BIN_DIR" ]; then
	case ":$PATH:" in *":$BRAIN_BIN_DIR:"*) : ;; *) PATH="$BRAIN_BIN_DIR:$PATH" ;; esac
	_rc=""
	case "${SHELL##*/}" in
		fish) command -v fish >/dev/null 2>&1 && fish -c "contains -- $BRAIN_BIN_DIR \$fish_user_paths; or fish_add_path -U $BRAIN_BIN_DIR" >/dev/null 2>&1 || true ;;
		bash) _rc="$HOME/.bashrc" ;;
		*)    _rc="$HOME/.zshrc" ;;
	esac
	if [ -n "$_rc" ] && ! grep -qF "$BRAIN_BIN_DIR" "$_rc" 2>/dev/null; then
		# shellcheck disable=SC2016  # literal $PATH wanted — the rc expands it at shell startup
		printf '
export PATH="%s:$PATH"
' "$BRAIN_BIN_DIR" >> "$_rc"
		echo "PATH persisted: $BRAIN_BIN_DIR -> ${_rc##*/}"
	fi
fi

echo ""
echo "agentBrain setup · ${PLATFORM}"
echo "${VAULT}"
# Only surface the install base when it's not the normal default (advanced/sandbox).
[ "${AGENTBRAIN_HOME}" != "$HOME" ] && echo "Config base: ${AGENTBRAIN_HOME}"
echo ""

# ── Step 1: Dependencies check ──────────────────────────

MISSING_DEPS=false

# Preflight: presence + minimal version of everything ab and its advanced addons
# need (OS-gated). Skips what is already fine; gates on the bootstrap trio
# (Xcode CLT / git / python3) and guides the user instead of tripping a GUI prompt
# mid-run. Node/bun/brew are reported but not gated — setup installs those.
bash "${SCRIPTS}/check-prerequisites.sh" || exit 1

# Recommended tools (nvm/Node, bun, uv) — the preflight above only REPORTS them.
# Offer the platform-aware installer here so a Linux/WSL install is not left
# with hints pointing at a script that never ran (macOS bootstrap runs it
# earlier, so this stays silent there). One consent, then unattended.
if ! command -v node &>/dev/null || ! command -v bun &>/dev/null; then
	if confirm "Install the missing recommended tools now? (nvm/Node LTS, bun, uv)" "Later: bash scripts/install-prerequisites.sh" Y; then
		AGENTBRAIN_ASSUME_YES=1 bash "${SCRIPTS}/install-prerequisites.sh" || \
			echo -e "${YELLOW}!${NC} Recommended-tools install had issues. Later: bash scripts/install-prerequisites.sh"
		# Loads tools installed seconds ago (rc edits are not sourced here).
		# shellcheck disable=SC1091
		source "${SCRIPTS}/lib/_toolpaths.sh"
	else
		echo "  Skipped. Later: bash scripts/install-prerequisites.sh"
	fi
fi

if ! command -v git &>/dev/null; then
	echo -e "${YELLOW}Missing${NC}  git (required)"
	MISSING_DEPS=true
fi

if ! command -v python3 &>/dev/null; then
	echo -e "${YELLOW}Missing${NC}  python3 (required for UUID5 generation)"
	MISSING_DEPS=true
fi

if [ "$MISSING_DEPS" = true ]; then
	if command -v brew &>/dev/null && confirm "Install missing dependencies via Homebrew?"; then
		command -v git &>/dev/null || brew install git
		command -v python3 &>/dev/null || brew install python3
	elif command -v apt-get &>/dev/null && confirm "Install missing dependencies via apt?"; then
		sudo apt-get update -qq
		command -v git &>/dev/null || sudo apt-get install -y git
		command -v python3 &>/dev/null || sudo apt-get install -y python3
	else
		echo "Please install git and python3, then re-run setup."
		exit 1
	fi
fi

# ── Step 2: Structure creation ─────────────────────────────

# Setup is a modular orchestrator: each step is a self-contained subscript that also runs
# standalone (each resolves VAULT itself). Steps are labelled, not numbered — the set varies
# (optional agent-CLI install, optional Pi), so a fixed "N/6" would misrepresent.
log() { printf '\n→ %s\n' "$*"; }

# Vault MUST run before Structure: if local/ becomes a symlink to a shared vault,
# Structure's `mkdir -p local/...` then populates the vault through the link.
log "Private vault"
bash "${SCRIPTS}/setup-local-vault.sh"

log "Structure"
bash "${SCRIPTS}/setup-structure.sh"

# Brain config MUST run before templates: templates carry {{uuid5}} placeholders
# that resolve via uuid5-gen.sh, which reads brain.json["namespace"].
log "Brain config"
bash "${SCRIPTS}/setup-brain-config.sh"

log "Templates & preferences"
bash "${SCRIPTS}/setup-templates.sh"

# Optional, opt-in: install agent CLIs the user doesn't have yet (agnostic — no agent is a
# default). Runs before connecting so freshly-installed agents get picked up below. Skips
# itself non-interactively (agentBrain never auto-installs an agent).
log "Agent CLIs (optional)"
bash "${SCRIPTS}/install-agent-clis.sh"

log "Connecting your AI tools"
export PLATFORM
bash "${SCRIPTS}/setup-agent-integrations.sh"

log "Git hooks"
bash "${SCRIPTS}/setup-git-hooks.sh"

log "Git identity"
# The vault autosync and spaces COMMIT; a clean machine has no git identity yet
# ("Author identity unknown"). Guarantee one here, so the first commit cannot
# fail — /onboard's identity step then confirms/refines it. (DEPENDENCY-MAP gap 1)
if [ -z "$(git config user.name 2>/dev/null)" ] || [ -z "$(git config user.email 2>/dev/null)" ]; then
	echo -e "${YELLOW}No git identity configured${NC} — commits (vault autosync, spaces) need user.name + user.email."
	if [ ! -t 0 ]; then
		echo "  Skipped (non-interactive). Set later: git config --global user.name / user.email — /onboard will also offer this."
	else
		read -r -p "  Your name for commits: " _gid_name
		read -r -p "  Your email for commits: " _gid_email
		if [ -n "$_gid_name" ] && [ -n "$_gid_email" ]; then
			git config --global user.name "$_gid_name"
			git config --global user.email "$_gid_email"
			echo -e "${GREEN}✓${NC}  git identity set (global): ${_gid_name} <${_gid_email}>"
		else
			echo "  Skipped — set it later; /onboard will offer this."
		fi
	fi
else
	echo "git identity: $(git config user.name) <$(git config user.email)>"
fi

log "Health check"
bash "${SCRIPTS}/setup-validation.sh"

# ── Detect Pi and guide to next step ─────────────────────────────

PI_INSTALLED=false
PI_VERSION=""
if command -v pi &>/dev/null; then
	PI_INSTALLED=true
	# pi --version output varies (and can be empty); only show it if non-empty.
	# `| head -1` can SIGPIPE `pi`, which under `set -o pipefail` would abort
	# setup — guard with `|| true` so a version probe never kills the install.
	PI_VERSION=$(pi --version 2>/dev/null | head -1 | tr -d '[:space:]' || true)
fi

# ── Setup complete ─────────────────────────────────────────

echo ""
echo "Setup complete."

# If Pi is installed, offer the deep integration (extensions + skills) right away.
# Skippable for headless/CI via AGENTBRAIN_SKIP_PI=1.
if [ "${AGENTBRAIN_SKIP_PI:-}" = 1 ]; then
	echo "Pi configuration skipped (AGENTBRAIN_SKIP_PI=1)."
elif [ "$PI_INSTALLED" = true ]; then
	pi_label="Pi detected"
	[ -n "$PI_VERSION" ] && pi_label="Pi detected (${PI_VERSION})"
	echo -e "${BLUE}${pi_label}${NC} — the deep integration symlinks Pi's extensions + skills and points Pi at this brain."
	if confirm "Configure Pi now?" "Pi is installed; this is the deep agentBrain integration." Y; then
		# The user just confirmed the Pi step; pass that consent down so
		# configure-pi.sh's own install prompts (opensrc) don't re-ask.
		# Runs via the one wiring primitive (`brain wire`, brain.sh).
		if AGENTBRAIN_ASSUME_YES=1 bash "${SCRIPTS}/brain.sh" wire --pi; then
			echo -e "${GREEN}✓${NC} Pi configured."
		else
			echo -e "${YELLOW}!${NC} Pi configuration had issues. Run manually: bash scripts/configure-pi.sh"
		fi
	else
		echo "Skipped. Run later: bash scripts/configure-pi.sh"
	fi
else
	echo "Using Pi? Install it, then run: bash scripts/configure-pi.sh"
fi

# ── Optional: daily self-improving loop (macOS only) ─────────────────────────
# The loop runs loop-tick.sh once a day: captures findings, renders the triage
# backlog, and refreshes startup-context so every session starts fresh.
# Opt-in: the plist is never installed silently — the user must choose.
if [ "$(uname)" = "Darwin" ] && [ "${AGENTBRAIN_HOME}" = "$HOME" ]; then
	LOOP_PLIST="${HOME}/Library/LaunchAgents/dev.agentbrain.loop.plist"
	if [ ! -f "$LOOP_PLIST" ]; then
		echo ""
		echo -e "${BLUE}Self-improving loop${NC} — runs loop-tick.sh once daily (captures findings,"
		echo "  renders triage backlog, refreshes startup-context). macOS launchd job."
		if confirm "Enable the daily self-improving loop?" "Install later: bash scripts/setup-launchd-loop.sh" N; then
			if bash "${SCRIPTS}/setup-launchd-loop.sh"; then
				echo -e "${GREEN}✓${NC} Daily loop enabled (dev.agentbrain.loop)."
			else
				echo -e "${YELLOW}!${NC} Loop install had issues. Run manually: bash scripts/setup-launchd-loop.sh"
			fi
		else
			echo "  Skipped. Enable later: bash scripts/setup-launchd-loop.sh"
		fi
	fi
fi

log "Personalize (optional)"
# Core onboarding WITHOUT an AI model: the fixed-choice intake as terminal menus
# (scripts/onboard-wizard.sh). Deliberately the CLOSING step — after Pi config
# and the loop, so no technical output ever interrupts the human questions.
# Optional — /onboard inside an agent later deepens via its skip-if-done contract.
if bash "${SCRIPTS}/check-onboarding.sh" >/dev/null 2>&1; then
	echo "Already personalized — /onboard can refine anytime."
elif [ -t 0 ] || { [ -e /dev/tty ] && ( : < /dev/tty ) 2>/dev/null; }; then
	if confirm "Personalize your brain now? (2 minutes, no AI needed)" "Run later: brain onboard — or /onboard inside your agent." Y; then
		bash "${SCRIPTS}/onboard-wizard.sh" || echo "  Wizard skipped/failed — /onboard inside your agent covers the same ground."
	else
		echo "  Skipped. Later: brain onboard — or /onboard inside your agent."
	fi
else
	echo "Non-interactive — skipped. Later: brain onboard — or /onboard inside your agent."
fi

# Next steps
echo ""
echo "Next:"
echo "  /onboard                  personalize preferences, addons and locale (run inside your agent)"
echo "  brain status              what's connected (dev/live)"
echo "  brain doctor              re-check health anytime"
echo "  brain wire                re-link skills + Pi after an update or rename"
echo "  brain --help              the full CLI (update, channel, addons, ...)"
# Surface onboarding completeness (gap G2 seam / E2): make "installed but not
# personalized" visible, instead of a hint that is easy to ignore.
if ! bash "${SCRIPTS}/check-onboarding.sh" >/dev/null 2>&1; then
	echo ""
	echo -e "${YELLOW}⚠ Installed, but your brain is not personalized yet.${NC}"
	echo "  Run /onboard inside your agent — or 'bash scripts/check-onboarding.sh' to see what's missing."
fi
# The brain IS a ready-made Obsidian vault — offer the human viewer here where
# a one-command install exists (opt-in, N default): brew on macOS, flatpak/snap
# on Linux. WSL runs GUI apps on the Windows side, so it gets the winget hint
# and the \\wsl$ vault path instead of a cross-OS install attempt. Editors stay
# out of setup: they serve your code, not the brain; Obsidian serves the brain.
OBSIDIAN_CMD=""
if [ "${AGENTBRAIN_HOME}" = "$HOME" ] && ! { [ -d "/Applications/Obsidian.app" ] || command -v obsidian &>/dev/null; }; then
	if [ "$(uname)" = "Darwin" ] && command -v brew &>/dev/null; then
		OBSIDIAN_CMD="brew install --cask obsidian"
	elif [ -z "${WSL_DISTRO_NAME:-}" ] && [ "$(uname)" = "Linux" ]; then
		if command -v flatpak &>/dev/null; then
			OBSIDIAN_CMD="flatpak install -y flathub md.obsidian.Obsidian"
		elif command -v snap &>/dev/null; then
			OBSIDIAN_CMD="sudo snap install obsidian --classic"
		fi
	fi
fi
if [ -d "/Applications/Obsidian.app" ] || command -v obsidian &>/dev/null; then
	echo "  Obsidian (graph + search): ${VAULT}"
elif [ -n "$OBSIDIAN_CMD" ]; then
	if confirm "Install Obsidian? (the brain is a ready-made vault: graph, backlinks, search)" "Later: ${OBSIDIAN_CMD} — then open: ${VAULT}" N; then
		if $OBSIDIAN_CMD; then
			echo -e "  ${GREEN}✓${NC} Obsidian installed — open the vault: ${VAULT}"
		else
			echo -e "  ${YELLOW}!${NC} Obsidian install had issues. Later: ${OBSIDIAN_CMD}"
		fi
	else
		echo "  Skipped. Later: ${OBSIDIAN_CMD} — then open: ${VAULT}"
	fi
elif [ -n "${WSL_DISTRO_NAME:-}" ]; then
	echo "  Obsidian: install it on the Windows side (winget install Obsidian.Obsidian),"
	_wsl_vault="$(printf '%s' "${VAULT}" | tr '/' "\\\\")"
	printf '  then open the vault via \\\\wsl$\\%s%s\n' "${WSL_DISTRO_NAME}" "${_wsl_vault}"
else
	echo "  Obsidian (https://obsidian.md), then open: ${VAULT}"
fi
