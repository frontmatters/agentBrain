#!/usr/bin/env bash
# configure-pi.sh — Configure Pi coding agent with agentBrain extensions, skills, and tsconfig.
# Symlinks extensions + skills into ~/.pi/agent/, generates machine-specific tsconfig.json,
# checks Pi API compatibility, and verifies credentials.
# Idempotent — safe to re-run after Pi updates.
#
# Called by: scripts/bootstrap-macos.sh
# Can also be run standalone to reconfigure Pi after an update.

set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
# Route Pi's symlinks through the active-brain alias when it exists, so a future
# `brain use dev|live` flips them via one link. Fall back to the checkout.
BRAIN_ALIAS="${BRAIN_ALIAS:-${AGENTBRAIN_HOME:-$HOME}/agentBrain}"
PI_SRC="$AGENTBRAIN_DIR"
[ -e "$BRAIN_ALIAS" ] && PI_SRC="$BRAIN_ALIAS"
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

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\n%bWARN%b: %s\n' "${YELLOW}" "${NC}" "$*" >&2; }
ok() { printf '%b✓%b  %s\n' "${GREEN}" "${NC}" "$*"; }

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

	log "Installing Pi coding agent"
	npm install -g @earendil-works/pi-coding-agent
	ok "Pi installed"
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

	log "Installing opensrc (dependency source-code access for agents)"
	bun add -g opensrc
	ok "opensrc installed"
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

	sed "s|__PI_MODULES__|${pi_mods}|g" "$template" >"$output"
	ok "tsconfig.json generated (Pi modules: $pi_mods)"
}

# Link enabled add-ons' SKILL.md into Pi's skills dir, via the shared lib so Pi
# stays in lockstep with Claude Code/Copilot (setup-skills.sh) — enabled => available.
link_addon_skills() {
	skilllib_sync_addon_skills "$PI_CONFIG_DIR/skills" "$PI_SRC/system/addons" "${ADDONS_STATE:-$PI_SRC/local/addons}" "$PI_SRC"
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

	# Core agentBrain skills (canonical home: system/skills/; GitHub Copilot
	# reads the same skills via .github/skills/ symlinks).
	for skill in brain-review onboard project-update save-learning save-troubleshoot opensrc; do
		local source="$PI_SRC/system/skills/$skill"
		if [[ -d "$source" ]]; then
			link_file "$source" "$PI_CONFIG_DIR/skills/$skill"
		fi
	done

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
}

# ── Extension validation ──────────────────────────────────────────────────────

validate_extensions() {
	command -v pi >/dev/null 2>&1 || return
	local failed=0
	for ext in "$PI_CONFIG_DIR"/extensions/*.ts; do
		[[ -e "$ext" ]] || continue
		pi --offline --no-extensions -e "$ext" --list-models nonexistent >/dev/null 2>&1 || {
			warn "Extension validation failed: $(basename "$ext")"
			failed=1
		}
	done
	[[ $failed -eq 0 ]] && ok "Extensions load cleanly"
}

# ── Pi credentials ────────────────────────────────────────────────────────────

maybe_pi_keychain_setup() {
	if [[ -f "$HOME/Library/Keychains/pi-agent.keychain-db" ]]; then
		ok "pi-agent keychain exists"
		return
	fi
	if [[ -f "$PI_CONFIG_DIR/auth.json" ]]; then
		warn "Pi auth.json found but no pi-agent keychain. Consider migrating with scripts/setup-pi-keychain-macos.sh."
	else
		warn "No Pi credentials found. Use /login in Pi or restore credentials manually."
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
	maybe_pi_keychain_setup
	echo ""
	ok "Pi configuration done"
}

# Run main only when executed directly; sourcing (e.g. from tests) loads the
# helpers without performing an install.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
