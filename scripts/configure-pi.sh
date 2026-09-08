#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# configure-pi.sh — Configure Pi coding agent with agentBrain extensions, skills, and tsconfig.
# Symlinks extensions + skills into ~/.pi/agent/, generates machine-specific tsconfig.json,
# checks Pi API compatibility, and verifies credentials.
# Idempotent — safe to re-run after Pi updates.
#
# Called by: scripts/installer/bootstrap/macos.sh
# Can also be run standalone to reconfigure Pi after an update.

set -euo pipefail

# shellcheck disable=SC1091
. "$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)/installer/prompt-helper.sh"

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
# Route Pi's symlinks through the active-brain alias when it exists, so a future
# `brain use dev|live` flips them via one link. Fall back to the checkout.
BRAIN_ALIAS="${BRAIN_ALIAS:-${AGENTBRAIN_HOME:-$HOME}/agentBrain}"
PI_SRC="$AGENTBRAIN_DIR"
# Only a symlink is an active-brain alias. A plain directory at ~/agentBrain
# may be stale user data and must never shadow the canonical checkout.
[ -L "$BRAIN_ALIAS" ] && [ -e "$BRAIN_ALIAS" ] && PI_SRC="$BRAIN_ALIAS"
PI_CONFIG_DIR="${PI_CONFIG_DIR:-${AGENTBRAIN_HOME:-$HOME}/.pi/agent}"
PI_CONFIG_SOURCE="${PI_CONFIG_SOURCE:-$PI_SRC/system/pi-config}"

# Optional secrets-helper (legacy opt-in): set SECRETS_HELPER_REPO to install it
# during Pi setup. The install logic now lives in the agent-agnostic add-on
# (system/addons/secrets-helper); this only delegates to it. Canonical standalone
# install: bash scripts/addons.sh install secrets-helper
SECRETS_HELPER_REPO="${SECRETS_HELPER_REPO:-}"
SECRETS_HELPER_DIR="${SECRETS_HELPER_DIR:-$HOME/Developer/secrets-helper}"
SECRETS_HELPER_RUN_SETUP="${SECRETS_HELPER_RUN_SETUP:-auto}"

export PI_CONFIG_DIR PI_CONFIG_SOURCE

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Shared addon-skill linking — one source of truth with setup-skills.sh (Claude/Copilot).
# shellcheck disable=SC1091  # dynamic source path; lib/skills.sh is shellcheck-clean on its own
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/skills.sh"

# Load user-scoped tool paths (nvm/brew/bun) via the shared lib — it guards the
# set -u hazards inside nvm.sh; a bare `nvm use` here died on an unbound variable.
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/_toolpaths.sh"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\n%bWARN%b: %s\n' "${YELLOW}" "${NC}" "$*" >&2; }
ok() { printf '%b✓%b  %s\n' "${GREEN}" "${NC}" "$*"; }

# Same prompt policy as install-prerequisites.sh (_proceed_install): install only
# with AGENTBRAIN_ASSUME_YES=1 (setup.sh exports it after its own confirm) or an
# interactive yes. A bare non-TTY run never installs software unasked.
_proceed_install() {
	[ "${AGENTBRAIN_ASSUME_YES:-}" = "1" ] && return 0
	if [ -t 0 ]; then
		# Pi and opensrc are part of the installer's Step 3 — Enter installs.
		ab_prompt_confirm --default yes "Install $1?" && return 0 || return 1
	fi
	return 1
}

# ── helpers ───────────────────────────────────────────────────────────────────

backup_if_real_file() {
	local target="$1"
	if [[ -e "$target" && ! -L "$target" ]]; then
		local backup
		backup="$target.backup.$(date +%Y%m%d-%H%M%S)"
		mv "$target" "$backup"
		echo "Backed up $target -> $backup"
	fi
}

link_file() {
	local source="$1" target="$2"
	mkdir -p "$(dirname "$target")"
	if [[ -L "$target" ]]; then rm "$target"; fi
	backup_if_real_file "$target"
	ln -s "$source" "$target"
}

# ── Pi install ───────────────────────────────────────────────────────────────

ensure_pi() {
	if command -v pi >/dev/null 2>&1; then
		ok "Pi already installed"
		return
	fi

	if _proceed_install "Pi (npm install -g @earendil-works/pi-coding-agent)"; then
		log "Installing Pi coding agent"
		npm install -g @earendil-works/pi-coding-agent
		ok "Pi installed"
	else
		warn "Pi not installed (no confirmation — re-run with AGENTBRAIN_ASSUME_YES=1 or answer yes on a TTY). Manual: npm install -g @earendil-works/pi-coding-agent"
	fi
}

# ── opensrc ───────────────────────────────────────────────────────────────
# TODO: move to scripts/addons.sh once the add-ons layer is implemented.

ensure_opensrc() {
	if command -v opensrc >/dev/null 2>&1; then
		ok "opensrc already installed"
		return
	fi

	if ! command -v bun >/dev/null 2>&1; then
		warn "bun not found — skipping opensrc. Install bun first: https://bun.sh"
		return
	fi

	# Version knob for reproducible installs; defaults to latest (non-blocking).
	local opensrc_version="${AGENTBRAIN_OPENSRC_VERSION:-latest}"
	if _proceed_install "opensrc (bun add -g opensrc@${opensrc_version})"; then
		log "Installing opensrc (dependency source-code access for agents)"
		bun add -g "opensrc@${opensrc_version}"
		ok "opensrc installed"
	else
		warn "opensrc not installed (no confirmation — re-run with AGENTBRAIN_ASSUME_YES=1 or answer yes on a TTY). Manual: bun add -g opensrc"
	fi
}

# ── Pi module location ────────────────────────────────────────────────────────

find_pi_modules() {
	local bun_mods="$HOME/.bun/install/global/node_modules"
	local npm_mods
	npm_mods="$(npm root -g 2>/dev/null)" || npm_mods=""

	if [[ -f "$bun_mods/@earendil-works/pi-coding-agent/dist/index.d.ts" ]]; then
		echo "$bun_mods"
	elif [[ -n "$npm_mods" && -f "$npm_mods/@earendil-works/pi-coding-agent/dist/index.d.ts" ]]; then
		echo "$npm_mods"
	else
		local found
		found=$(node -e "try{const p=require.resolve('@earendil-works/pi-coding-agent');console.log(require('path').join(p,'../../..'))}catch(e){}" 2>/dev/null) || found=""
		echo "$found"
	fi
}

# ── Pi API compatibility ──────────────────────────────────────────────────────

check_pi_api() {
	local pi_mods
	pi_mods="$(find_pi_modules)"
	[[ -n "$pi_mods" ]] || return

	local types_file="$pi_mods/@earendil-works/pi-coding-agent/dist/core/extensions/types.d.ts"
	[[ -f "$types_file" ]] || {
		warn "Pi types file not found at $types_file — skipping API check."
		return
	}

	# Symbols the extensions actively call. Update when extensions change.
	# Source: system/pi-config/extensions/extensions.md
	local required_symbols=(
		"getModel"            # extract-learnings.ts
		"modelRegistry"       # extract-learnings.ts
		"registerTool"        # agentbrain.ts, youtube-transcript.ts
		"registerCommand"     # multiple extensions
		"registerProvider"    # glm.ts, ollama-cloud.ts
		"appendEntry"         # goal.ts
		"sendMessage"         # goal.ts
		"agent_settled"       # goal.ts
		"isToolCallEventType" # git-interceptor.ts
	)

	local failed=0
	for sym in "${required_symbols[@]}"; do
		if ! grep -q "${sym}" "$types_file" 2>/dev/null; then
			warn "Pi API changed: '${sym}' not found in types.d.ts — check extensions that use it."
			failed=1
		fi
	done

	[[ $failed -eq 0 ]] && ok "Pi API symbols: all present"
}

# ── tsconfig generation ───────────────────────────────────────────────────────

generate_extension_tsconfig() {
	local template="$PI_CONFIG_SOURCE/extensions/tsconfig.template.json"
	local output="$PI_CONFIG_SOURCE/extensions/tsconfig.json"

	[[ -f "$template" ]] || {
		warn "tsconfig.template.json not found — skipping tsconfig generation."
		return
	}

	local pi_mods
	pi_mods="$(find_pi_modules)"

	if [[ -z "$pi_mods" ]]; then
		warn "Cannot locate Pi node_modules — tsconfig.json not generated. Editor type-checking will be limited."
		return
	fi

	# Dependencies (pi-ai, typebox) may be HOISTED to the global node_modules or
	# NESTED under pi-coding-agent/node_modules — npm decides per machine. Resolve
	# the location that actually exists instead of assuming hoisting.
	local pi_deps="$pi_mods"
	if [[ ! -d "$pi_mods/@earendil-works/pi-ai" && -d "$pi_mods/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai" ]]; then
		pi_deps="$pi_mods/@earendil-works/pi-coding-agent/node_modules"
	fi
	sed -e "s|__PI_MODULES__|${pi_mods}|g" -e "s|__PI_DEPS__|${pi_deps}|g" "$template" >"$output"
	ok "tsconfig.json generated (Pi modules: $pi_mods; deps: $pi_deps)"
}

# Link enabled add-ons' SKILL.md into Pi's skills dir, via the shared lib so Pi
# stays in lockstep with Claude Code/Copilot (setup-skills.sh) — enabled => available.
link_addon_skills() {
	skilllib_sync_addon_skills "$PI_CONFIG_DIR/skills" "$PI_SRC/system/addons" "${ADDONS_STATE:-$PI_SRC/vault/addons}" "$PI_SRC"
}

# ── Pi config install ─────────────────────────────────────────────────────────

install_pi_config() {
	log "Installing Pi config"
	mkdir -p "$PI_CONFIG_DIR/extensions" "$PI_CONFIG_DIR/skills" "$PI_CONFIG_DIR/bin"

	# Extensions: symlink each entry under system/pi-config/extensions/
	# Skip helper modules listed in .pi-ignore (not extensions themselves)
	if [[ -d "$PI_CONFIG_SOURCE/extensions" ]]; then
		local pi_ignore_file="$PI_CONFIG_SOURCE/extensions/.pi-ignore"
		local ignored_entries=()
		if [[ -f "$pi_ignore_file" ]]; then
			# Read .pi-ignore, skipping comments and blank lines
			while IFS= read -r line || [[ -n "$line" ]]; do
				# Skip comments and blank lines
				[[ "$line" =~ ^[[:space:]]*# ]] && continue
				[[ -z "${line// /}" ]] && continue
				ignored_entries+=("$line")
			done <"$pi_ignore_file"
		fi

		# Remove symlinks for entries in the ignore list
		for ignored in "${ignored_entries[@]}"; do
			local ignored_path="$PI_CONFIG_DIR/extensions/$ignored"
			if [[ -L "$ignored_path" ]]; then
				rm "$ignored_path"
				echo "Removed ignored entry: $ignored"
			fi
		done

		# Remove stale brain-owned extension symlinks before linking the canonical set.
		# This prevents an old extension (for example goal.ts) from surviving a release
		# that no longer ships its private dependency tree.
		for ext_link in "$PI_CONFIG_DIR"/extensions/*.ts; do
			[[ -L "$ext_link" ]] || continue
			ext_name="$(basename "$ext_link")"
			if [[ ! -e "$PI_CONFIG_SOURCE/extensions/$ext_name" ]]; then
				rm -f "$ext_link"
				echo "Removed stale extension: $ext_name"
			fi
		done

		for ext_source in "$PI_CONFIG_SOURCE"/extensions/*; do
			[[ -e "$ext_source" ]] || continue
			local ext_name
			ext_name="$(basename "$ext_source")"

			# Skip if this entry is in the ignore list
			for ignored in "${ignored_entries[@]}"; do
				[[ "$ext_name" == "$ignored" ]] && continue 2
			done

			link_file "$ext_source" "$PI_CONFIG_DIR/extensions/$ext_name"
		done
		ok "Extensions symlinked -> $PI_CONFIG_DIR/extensions/"
	fi

	# AGENTS.md: Pi expects ~/.pi/agent/AGENTS.md
	if [[ -f "$PI_CONFIG_SOURCE/agents.md" ]]; then
		link_file "$PI_CONFIG_SOURCE/agents.md" "$PI_CONFIG_DIR/AGENTS.md"
		ok "AGENTS.md linked"
	fi

	# Pi wrapper script: ensures PATH resolves custom bin/ before package-manager bins
	if [[ -f "$PI_CONFIG_SOURCE/bin/pi" ]]; then
		link_file "$PI_CONFIG_SOURCE/bin/pi" "$PI_CONFIG_DIR/bin/pi"
		chmod +x "$PI_CONFIG_SOURCE/bin/pi"
		ok "Pi wrapper linked -> $PI_CONFIG_DIR/bin/pi"
	fi

	# All agentBrain skills (system/skills + local/skills), via the shared lib so
	# Pi links the SAME standalone skills as Claude Code/Copilot (setup-skills.sh).
	# No hardcoded subset: a new skill in the brain can never be silently skipped
	# for Pi. Orphans (source deleted) are pruned, like the other agents.
	skilllib_link_standalone_skills "$PI_CONFIG_DIR/skills" "$PI_SRC/system/skills" "system/skills" "$PI_SRC"
	skilllib_link_standalone_skills "$PI_CONFIG_DIR/skills" "$PI_SRC/vault/skills" "vault/skills" "$PI_SRC"
	skilllib_prune_orphaned_skills "$PI_CONFIG_DIR/skills" "$PI_SRC"

	# Third-party skills tracked under system/pi-config/skills/
	if [[ -d "$PI_CONFIG_SOURCE/skills" ]]; then
		for skill_source in "$PI_CONFIG_SOURCE"/skills/*; do
			[[ -d "$skill_source" ]] || continue
			local skill_name
			skill_name="$(basename "$skill_source")"
			link_file "$skill_source" "$PI_CONFIG_DIR/skills/$skill_name"
		done
	fi

	# Skills shipped by enabled add-ons (mirrors Claude Code/Copilot).
	link_addon_skills

	ok "Skills symlinked -> $PI_CONFIG_DIR/skills/"

	# settings.json: copy on first install, merge on updates (not symlinked — Pi writes to it)
	if [[ -f "$PI_CONFIG_SOURCE/settings.json" ]]; then
		if [[ ! -f "$PI_CONFIG_DIR/settings.json" ]]; then
			cp "$PI_CONFIG_SOURCE/settings.json" "$PI_CONFIG_DIR/settings.json"
			ok "settings.json copied"
		else
			python3 - <<'PY'
import json, os, pathlib
src = pathlib.Path(os.environ['PI_CONFIG_SOURCE']) / 'settings.json'
dst = pathlib.Path(os.environ['PI_CONFIG_DIR']) / 'settings.json'
s = json.loads(src.read_text())
d = json.loads(dst.read_text())
# Preserve user choices; only sync package pins from shared config.
if 'packages' in s:
    d['packages'] = s['packages']
dst.write_text(json.dumps(d, indent=2) + '\n')
PY
			ok "settings.json merged"
		fi
	fi

	# cloak.json: copy on first install only. The pi-cloak extension reads it and
	# the user edits their own read-cloaking patterns, so never overwrite/merge on
	# updates. Absent = a "pi-cloak config not found" warning on every pi session,
	# so seed a valid default (enabled, empty patterns; the always-on bash secret
	# safety net runs regardless — see system/pi-config/extensions/pi-cloak/).
	if [[ -f "$PI_CONFIG_SOURCE/cloak.json" && ! -f "$PI_CONFIG_DIR/cloak.json" ]]; then
		cp "$PI_CONFIG_SOURCE/cloak.json" "$PI_CONFIG_DIR/cloak.json"
		ok "cloak.json copied (pi-cloak default)"
	fi
}

# ── Extension validation ──────────────────────────────────────────────────────

validate_extensions() {
	command -v pi >/dev/null 2>&1 || return

	# `--list-models` exits BEFORE extensions are evaluated, so the previous
	# invocation reported "loads cleanly" for an extension importing a module
	# that does not exist (verified with a deliberately broken extension). That
	# false green is how a broken goal.ts reached two machines while this line
	# kept printing a tick.
	#
	# `--print` does load them. It fails fast on a broken extension and keeps
	# running on a healthy one, so the check is bounded and judged on the
	# message, not the exit code: hitting the timeout means loading succeeded.
	# One run loads every extension from settings; only when that reports a
	# failure is it worth paying a timeout per extension to name the culprit.
	local probe
	# `|| true`: pi exits non-zero here (no provider in offline mode), and under
	# set -e that failing pipeline would abort configure-pi silently, mid-run.
	probe="$(perl -e 'alarm 25; exec @ARGV' -- pi --offline --print noop 2>&1 | head -40 || true)"
	if ! printf '%s' "$probe" | grep -q "Failed to load extension"; then
		ok "Extensions load cleanly"
		return
	fi

	# The probe names the culprit itself. Looping per extension does not help
	# and actively misleads: `pi -e <ext>` still loads everything from settings,
	# so every run trips over the same broken extension and each iteration
	# blamed whichever file it happened to be passing.
	printf '%s\n' "$probe" \
		| grep -o 'Failed to load extension "[^"]*"' \
		| sed 's/.*"\(.*\)"/\1/' | sort -u \
		| while read -r bad; do warn "Extension failed to load: $(basename "$bad")"; done
	printf '%s\n' "$probe" | grep -m1 "Cannot find module" | sed 's/^/         /'
}

# ── Pi credentials ────────────────────────────────────────────────────────────

maybe_pi_keychain_setup() {
	if [[ "$(uname -s)" != "Darwin" ]]; then
		if [[ -f "$PI_CONFIG_DIR/auth.json" ]]; then
			warn "Pi credentials are present in auth.json. secrets-helper uses macOS Keychain and is not available on this platform. Use the operating system's user secret store; do not paste API keys into shell commands."
		fi
		return
	fi
	if [[ -f "$HOME/Library/Keychains/pi-agent.keychain-db" ]]; then
		ok "pi-agent keychain exists"
		return
	fi
	if [[ -f "$PI_CONFIG_DIR/auth.json" ]]; then
		warn "Pi credentials are present in auth.json, but no pi-agent keychain was detected. The optional secrets-helper can migrate supported credentials to macOS Keychain. Do not paste API keys into shell commands."
	else
		warn "No Pi credentials found. Use /login in Pi or restore credentials manually."
	fi
}

# Offer the macOS-only credential migration at the end of Pi setup, after the
# user has seen the risk. It remains opt-in and never runs on Linux/WSL.
offer_secrets_helper() {
	[[ "$(uname -s)" = "Darwin" ]] || return 0
	local addon="$PI_SRC/system/addons/secrets-helper/install.sh"
	[[ -x "$addon" ]] || return 0
	local installed=0
	[[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/secrets-helper/config.sh" ]] && installed=1
	# Installed: show it — never silently pass.
	if [ "$installed" = 1 ]; then
		if ab_prompt_select --default 3 "secrets-helper: what should we do?" \
			"keep — installed and configured" \
			"reinstall — run the setup wizard again" \
			"skip — continue without changes"; then
			# REPLY is the zero-based row index: 0=keep, 1=reinstall, 2=skip.
			case "$REPLY" in
				0) : ;;
				1) ADDONS_ASSUME_YES=1 bash "$PI_SRC/scripts/addons.sh" install secrets-helper ;;
				*) echo "  Skipped." ;;
			esac
		fi
		return 0
	fi
	# Not installed: only offer when there are credentials to migrate.
	[[ -f "$PI_CONFIG_DIR/auth.json" ]] || return 0
	echo ""
	echo "Optional security setup"
	echo "Pi credentials are currently stored in auth.json."
	echo "secrets-helper can migrate supported credentials to the macOS Keychain."
	if [[ -t 0 ]] && ab_prompt_confirm --default no "Install secrets-helper now?"; then
		ADDONS_ASSUME_YES=1 bash "$PI_SRC/scripts/addons.sh" install secrets-helper
	else
		echo "Skipped. Run later: bash scripts/addons.sh install secrets-helper"
	fi
}

# ── Optional: secrets-helper (delegated to the add-on) ───────────────────────
# secrets-helper is agent-agnostic, so the install logic lives in the add-on
# (system/addons/secrets-helper/install.sh): brew-first, public git-clone
# fallback, idempotent, macOS-guarded. This function only delegates, preserving
# the legacy SECRETS_HELPER_REPO opt-in gate so Pi setup behaviour is unchanged.

install_secrets_helper() {
	[[ -n "$SECRETS_HELPER_REPO" ]] || return 0

	local addon="$PI_SRC/system/addons/secrets-helper/install.sh"
	if [[ ! -x "$addon" ]]; then
		warn "secrets-helper add-on not found at $addon"
		return 0
	fi

	# Map the legacy 1/0/auto toggle to the add-on's yes/no/auto vocabulary.
	local run_setup="$SECRETS_HELPER_RUN_SETUP"
	case "$run_setup" in 1) run_setup=yes ;; 0) run_setup=no ;; esac

	log "Installing secrets-helper via add-on"
	SECRETS_HELPER_DIR="$SECRETS_HELPER_DIR" SECRETS_HELPER_RUN_SETUP="$run_setup" bash "$addon"
}

# ── main ─────────────────────────────────────────────────────────────────────

main() {
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	echo "Configure Pi"
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	ensure_pi
	ensure_opensrc
	check_pi_api
	install_pi_config
	generate_extension_tsconfig
	validate_extensions
	install_secrets_helper
	offer_secrets_helper
	maybe_pi_keychain_setup
	echo ""
	ok "Pi configuration done"
}

# Run main only when executed directly; sourcing (e.g. from tests) loads the
# helpers without performing an install.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
