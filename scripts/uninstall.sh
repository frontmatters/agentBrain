#!/usr/bin/env bash
# uninstall.sh — Remove agentBrain pointers, symlinks, env vars.
# Safe: does NOT delete the checkout itself unless explicitly requested.

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
# Install base, mirroring setup.sh: pointers live under AGENTBRAIN_HOME (default $HOME).
# Keeping this symmetric is what lets uninstall actually remove what setup wrote.
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Flags: --yes auto-confirms the proceed prompts (headless/CI). Deleting the checkout
# always needs an explicit --delete-checkout (never folded into --yes — too destructive).
# --purge also removes local/addons/<id>/ config dirs for enabled addons.
ASSUME_YES=false
DELETE_CHECKOUT=false
PURGE_ADDON_CONFIGS=false
for _arg in "$@"; do
	case "$_arg" in
	--yes | -y | --non-interactive) ASSUME_YES=true ;;
	--delete-checkout) DELETE_CHECKOUT=true ;;
	--purge) PURGE_ADDON_CONFIGS=true ;;
	-h | --help)
		cat <<'EOF'
agentBrain uninstall — remove agent connectors, Pi symlinks, the brain alias, and env vars.

Usage:
  ./scripts/uninstall.sh                  Interactive.
  ./scripts/uninstall.sh --yes            Non-interactive (auto-confirm; for CI/agents).
  ./scripts/uninstall.sh --purge          Also remove local/addons/<id>/ config dirs.
  ./scripts/uninstall.sh --delete-checkout  Also delete the checkout (requires confirmation
                                          unless combined with --yes). The checkout is kept by default.

Environment:
  AGENTBRAIN_HOME=PATH   Install base to clean (default: $HOME) — match what setup used.
EOF
		exit 0
		;;
	esac
done

# confirm <prompt> — true on yes. With --yes, always true. Non-TTY without --yes: abort-safe false.
confirm() {
	if [ "$ASSUME_YES" = true ]; then return 0; fi
	if [ -t 0 ]; then
		read -p "$1 [y/N] " -n 1 -r
		echo
		[[ $REPLY =~ ^[Yy]$ ]]
		return
	fi
	return 1
}

REMOVED=0
SKIPPED=0

log_removed() {
	echo -e "${GREEN}Removed${NC}  $1"
	REMOVED=$((REMOVED + 1))
}
log_skip() {
	echo -e "${YELLOW}Skip${NC}    $1 (not found)"
	SKIPPED=$((SKIPPED + 1))
}
log_warn() {
	echo -e "${YELLOW}Warn${NC}    $1" >&2
}

# remove_pointer_block <file> — remove ONLY our pointer block from <file>: from
# the "## agentBrain" heading (or the legacy "# agentBrain" h1) up to the next
# "## " heading, preserving everything after the block. (The old sed '…,$d'
# wiped the rest of the file, including user content below our block.)
# A timestamped backup of the original file is kept next to it.
remove_pointer_block() {
	local file="$1" backup
	backup="${file}.agentbrain-uninstall-$(date +%Y%m%d-%H%M%S).bak"
	cp "$file" "$backup"
	awk 'BEGIN{skip=0} /^##? agentBrain/{skip=1;next} skip&&/^## /{skip=0} !skip{print}' \
		"$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
	# Trim trailing blank lines left where the block was removed.
	sed -i.sedbak -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$file"
	rm -f "${file}.sedbak"
	echo "          (backup: ${backup})"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "agentBrain uninstall"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Checkout: ${VAULT}"
echo ""
echo "This will remove agent pointers, Pi symlinks, and the VAULT env var."
echo "The checkout itself will NOT be deleted unless you explicitly choose to."
echo ""

# Suggest offboarding first if local/ has content
LOCAL_COUNT=$(find "${VAULT}/local" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$LOCAL_COUNT" -gt 0 ]]; then
	echo "⚠️  You have ${LOCAL_COUNT} local files (preferences, projects, learnings)."
	echo "   Consider running 'bash scripts/offboard.sh' first to export them."
	echo ""
	confirm "Continue anyway?" || {
		echo "Aborted. Run offboard.sh first (or pass --yes to skip this prompt)."
		exit 0
	}
else
	confirm "Proceed with uninstall?" || {
		echo "Aborted. (Pass --yes to skip this prompt.)"
		exit 0
	}
fi

# ── 1. Remove agent pointers ─────────────────

# Claude — remove ONLY our block; anything the user wrote below it stays.
# Detection matches the removal pattern (^##? agentBrain), covering the legacy h1 marker too.
CLAUDE_MD="$AGENT_HOME/.claude/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]] && grep -qE '^##? agentBrain' "$CLAUDE_MD" 2>/dev/null; then
	remove_pointer_block "$CLAUDE_MD"
	log_removed "Claude pointer (~/.claude/CLAUDE.md)"
elif [[ -f "$CLAUDE_MD" ]]; then
	log_skip "Claude pointer (marker not found)"
else
	log_skip "Claude (~/.claude/CLAUDE.md)"
fi

# Copilot / VS Code settings — legacy cleanup. Current setup writes NO settings key
# (Copilot reads instruction files, not settings; see setup-copilot.sh). Older versions
# wrote github.copilot.advanced.instructions — remove that if an agentBrain value lingers.
if [[ "$(uname)" = "Darwin" ]]; then
	VSCODE_CANDIDATES=(
		"$AGENT_HOME/Library/Application Support/Code/User/settings.json"
		"$AGENT_HOME/Library/Application Support/Code - Insiders/User/settings.json"
	)
else
	VSCODE_BASE="${XDG_CONFIG_HOME:-$AGENT_HOME/.config}"
	VSCODE_CANDIDATES=(
		"${VSCODE_BASE}/Code/User/settings.json"
		"${VSCODE_BASE}/Code - Insiders/User/settings.json"
	)
fi
for vsc_settings in "${VSCODE_CANDIDATES[@]}"; do
	if [[ -f "$vsc_settings" ]] && grep -q "agentBrain" "$vsc_settings" 2>/dev/null; then
		# Exit status is checked and stderr stays visible: a failed edit must warn,
		# never claim "Removed". VS Code settings.json is often JSONC (comments,
		# trailing commas), which strict json.load rejects — that case is caught
		# in Python and explained instead of silently skipped.
		if python3 - "$vsc_settings" <<'PY'
import json, sys
p = sys.argv[1]
try:
    with open(p) as f:
        cfg = json.load(f)
except json.JSONDecodeError as e:
    sys.stderr.write(
        f"cannot parse {p} as strict JSON (VS Code allows JSONC — comments/trailing commas): {e}\n")
    sys.exit(3)
adv = cfg.get('github.copilot.advanced')
if isinstance(adv, dict) and 'agentBrain' in str(adv.get('instructions', '')):
    adv.pop('instructions', None)
    if not adv:
        cfg.pop('github.copilot.advanced', None)
with open(p, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
PY
		then
			log_removed "Copilot legacy setting ($vsc_settings)"
		else
			log_warn "Could not update $vsc_settings — remove the 'github.copilot.advanced.instructions' key manually."
		fi
		break
	fi
done

# Copilot CLI — pointer appended to ~/.copilot/copilot-instructions.md; remove only our block.
COPILOT_CLI_INSTRUCTIONS="$AGENT_HOME/.copilot/copilot-instructions.md"
if [[ -f "$COPILOT_CLI_INSTRUCTIONS" ]] && grep -qE '^##? agentBrain' "$COPILOT_CLI_INSTRUCTIONS" 2>/dev/null; then
	remove_pointer_block "$COPILOT_CLI_INSTRUCTIONS"
	log_removed "Copilot CLI pointer (~/.copilot/copilot-instructions.md)"
else
	log_skip "Copilot CLI pointer"
fi

# Windsurf — setup writes into the detected config root (~/.codeium/windsurf or
# ~/.windsurf, see setup-windsurf.sh); clean both candidates, our block only.
windsurf_removed=false
for WINDSURF_RULES in "$AGENT_HOME/.codeium/windsurf/memories/global_rules.md" "$AGENT_HOME/.windsurf/memories/global_rules.md"; do
	if [[ -f "$WINDSURF_RULES" ]] && grep -qE '^##? agentBrain' "$WINDSURF_RULES" 2>/dev/null; then
		remove_pointer_block "$WINDSURF_RULES"
		log_removed "Windsurf pointer (${WINDSURF_RULES})"
		windsurf_removed=true
	fi
done
[[ "$windsurf_removed" == true ]] || log_skip "Windsurf pointer"

# Cline — setup writes its OWN rules file (never the user's .clinerules); remove it.
CLINE_FILE="$AGENT_HOME/Documents/Cline/Rules/agentBrain.md"
if [[ -f "$CLINE_FILE" ]]; then
	rm -f "$CLINE_FILE"
	log_removed "Cline pointer (~/Documents/Cline/Rules/agentBrain.md)"
else
	log_skip "Cline pointer"
fi
# Legacy cleanup: an older setup wrote the pointer block into .clinerules itself.
# Remove only our block (up to the next "## " heading) — never truncate to EOF.
CLINE_LEGACY="$AGENT_HOME/Documents/Cline/Rules/.clinerules"
if [[ -f "$CLINE_LEGACY" ]] && grep -qE '^##? agentBrain' "$CLINE_LEGACY" 2>/dev/null; then
	remove_pointer_block "$CLINE_LEGACY"
	# Drop the file if nothing but whitespace remains (the old setup wrote it whole).
	if [[ -f "$CLINE_LEGACY" ]] && ! grep -q '[^[:space:]]' "$CLINE_LEGACY" 2>/dev/null; then
		rm -f "$CLINE_LEGACY"
	fi
	log_removed "Cline legacy block (~/Documents/Cline/Rules/.clinerules)"
fi

# OpenCode — setup writes ~/.config/opencode/agentbrain-pointer.md and registers
# that path in the `instructions` array of ~/.config/opencode/opencode.json
# (matches setup-opencode.sh); remove both, symmetrically.
OPENCODE_DIR="$AGENT_HOME/.config/opencode"
OPENCODE_POINTER="$OPENCODE_DIR/agentbrain-pointer.md"
OPENCODE_JSON="$OPENCODE_DIR/opencode.json"
opencode_removed=false
if [[ -f "$OPENCODE_POINTER" ]]; then
	rm -f "$OPENCODE_POINTER"
	opencode_removed=true
fi
if [[ -f "$OPENCODE_JSON" ]] && grep -q "agentbrain-pointer.md" "$OPENCODE_JSON" 2>/dev/null; then
	if python3 - "$OPENCODE_JSON" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    cfg = json.load(f)
ins = cfg.get('instructions')
if isinstance(ins, list):
    ins = [i for i in ins if 'agentbrain-pointer.md' not in str(i)]
    if ins:
        cfg['instructions'] = ins
    else:
        cfg.pop('instructions', None)
with open(p, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
PY
	then
		opencode_removed=true
	else
		log_warn "Could not update $OPENCODE_JSON — remove the agentbrain-pointer.md entry from 'instructions' manually."
	fi
fi
if [[ "$opencode_removed" == true ]]; then
	log_removed "OpenCode pointer (~/.config/opencode/agentbrain-pointer.md + instructions entry)"
else
	log_skip "OpenCode pointer"
fi
# Legacy cleanup: an older setup appended our block to system_prompt in
# ~/.opencode/opencode.json; truncate system_prompt at the agentBrain marker.
OPENCODE_LEGACY="$AGENT_HOME/.opencode/opencode.json"
if [[ -f "$OPENCODE_LEGACY" ]] && grep -q "agentBrain" "$OPENCODE_LEGACY" 2>/dev/null; then
	if python3 - "$OPENCODE_LEGACY" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    cfg = json.load(f)
sp = cfg.get('system_prompt', '')
i = sp.find('# agentBrain')
if i != -1:
    sp = sp[:i].rstrip()
    if sp:
        cfg['system_prompt'] = sp
    else:
        cfg.pop('system_prompt', None)
with open(p, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
PY
	then
		log_removed "OpenCode legacy system_prompt block (~/.opencode/opencode.json)"
	else
		log_warn "Could not update $OPENCODE_LEGACY — remove the agentBrain block from 'system_prompt' manually."
	fi
fi

# Gemini CLI — remove only our block (same helper as the other pointer files).
GEMINI_MD="$AGENT_HOME/.gemini/GEMINI.md"
if [[ -f "$GEMINI_MD" ]] && grep -qE '^##? agentBrain' "$GEMINI_MD" 2>/dev/null; then
	remove_pointer_block "$GEMINI_MD"
	log_removed "Gemini CLI pointer (~/.gemini/GEMINI.md)"
else
	log_skip "Gemini CLI pointer"
fi

# Hermes — SOUL.md is the USER'S personality file: remove ONLY our block
# (from "## agentBrain" up to the next "## " heading or EOF), never the rest.
HERMES_SOUL="${HERMES_HOME:-$AGENT_HOME/.hermes}/SOUL.md"
if [[ -f "$HERMES_SOUL" ]] && grep -q "^## agentBrain" "$HERMES_SOUL" 2>/dev/null; then
	awk 'BEGIN{skip=0} /^## agentBrain/{skip=1;next} skip&&/^## /{skip=0} !skip{print}' \
		"$HERMES_SOUL" >"${HERMES_SOUL}.tmp" && mv "${HERMES_SOUL}.tmp" "$HERMES_SOUL"
	log_removed "Hermes pointer (~/.hermes/SOUL.md, rest of SOUL.md preserved)"
else
	log_skip "Hermes pointer"
fi

# Cursor — manual only
echo -e "${YELLOW}Manual${NC}  Cursor: remove agentBrain rules from Settings > Rules if added."

# ── 2. Remove Pi symlinks ──────────────────

PI_AGENT="$AGENT_HOME/.pi/agent"
PI_LINKS=(
	"${PI_AGENT}/extensions"
	"${PI_AGENT}/skills"
	"${PI_AGENT}/AGENTS.md"
	"${PI_AGENT}/bin/pi"
)
for link in "${PI_LINKS[@]}"; do
	if [[ -L "$link" ]]; then
		rm -f "$link"
		log_removed "Pi symlink: $(basename "$link")"
	elif [[ -e "$link" ]]; then
		echo -e "${YELLOW}Skip${NC}    $(basename "$link") (not a symlink, skipping)"
	else
		log_skip "Pi symlink: $(basename "$link")"
	fi
done

# Pi postinstall patch config
PI_PATCH_CONFIG="${PI_AGENT}/pi-postinstall-patch.json"
if [[ -f "$PI_PATCH_CONFIG" ]]; then
	rm -f "$PI_PATCH_CONFIG"
	log_removed "Pi postinstall patch config"
fi

# ── 1b. Remove active-brain alias + brain CLI (created by setup) ──

# Active-brain alias (~/agentBrain) — only if it's a symlink (never touch a real
# dir) AND it resolves to THIS checkout. An alias pointing at a sibling checkout
# (e.g. live while uninstalling dev) is that install's business — leave it.
BRAIN_ALIAS="$AGENT_HOME/agentBrain"
if [[ -L "$BRAIN_ALIAS" ]]; then
	alias_target="$(readlink "$BRAIN_ALIAS")"
	if [[ "$alias_target" == "$VAULT" ]]; then
		rm -f "$BRAIN_ALIAS"
		log_removed "Active-brain alias (${BRAIN_ALIAS})"
	else
		echo -e "${YELLOW}Skip${NC}    Active-brain alias points at another checkout (${alias_target}) — left in place"
		SKIPPED=$((SKIPPED + 1))
	fi
else
	log_skip "Active-brain alias"
fi

# brain CLI symlink — only if it resolves to THIS checkout's brain.sh.
for brain_bin in "$AGENT_HOME/bin/brain" "$AGENT_HOME/.local/bin/brain"; do
	if [[ -L "$brain_bin" ]]; then
		bin_target="$(readlink "$brain_bin")"
		if [[ "$bin_target" == "$VAULT/scripts/brain.sh" ]]; then
			rm -f "$brain_bin"
			log_removed "brain CLI (${brain_bin})"
		elif [[ "$bin_target" == *"brain.sh" ]]; then
			echo -e "${YELLOW}Skip${NC}    brain CLI (${brain_bin}) points at another checkout (${bin_target}) — left in place"
			SKIPPED=$((SKIPPED + 1))
		fi
	fi
done

# Brain skills installed into agents' native dirs (setup-skills.sh). Only remove symlinks
# that point into the brain's skill trees; never touch the user's own skills. The skill
# content itself lives in the brain (system/skills, local/skills) and is preserved.
removed_skills=0
for skills_dir in "$AGENT_HOME/.claude/skills" "$AGENT_HOME/.copilot/skills"; do
	[[ -d "$skills_dir" ]] || continue
	for link in "$skills_dir"/*; do
		[[ -L "$link" ]] || continue
		tgt="$(readlink "$link")"
		if [[ "$tgt" == *"/system/skills/"* || "$tgt" == *"/local/skills/"* ]]; then
			rm -f "$link"
			removed_skills=$((removed_skills + 1))
		fi
	done
	# Addon-provided skills are nested: <skills_dir>/<id>/SKILL.md -> .../system/addons/<id>/SKILL.md
	for entry in "$skills_dir"/*/; do
		skill="${entry}SKILL.md"
		[[ -L "$skill" ]] || continue
		if [[ "$(readlink "$skill")" == *"/system/addons/"* ]]; then
			rm -f "$skill"
			rmdir "$entry" 2>/dev/null || true
			removed_skills=$((removed_skills + 1))
		fi
	done
done
if [[ "$removed_skills" -gt 0 ]]; then
	log_removed "${removed_skills} brain skill symlink(s) from agent dirs"
else
	log_skip "brain skill symlinks"
fi

# ── 3. Remove agentBrain env vars from shell rc ─────────────────
# VAULT (written by setup) and AGENTBRAIN_LOCALE (written by onboarding).

for shell_rc in "$AGENT_HOME/.zshrc" "$AGENT_HOME/.bashrc"; do
	[[ -f "$shell_rc" ]] || continue
	for env_var in VAULT AGENTBRAIN_LOCALE; do
		if grep -q "^export ${env_var}=" "$shell_rc" 2>/dev/null; then
			sed -i.bak "/^export ${env_var}=/d" "$shell_rc"
			rm -f "${shell_rc}.bak"
			log_removed "${env_var} env var from ${shell_rc##*/}"
		fi
	done
done

# ── 4. Remove git hooks ─────────────────────

if git -C "$VAULT" config core.hooksPath &>/dev/null; then
	git -C "$VAULT" config --unset core.hooksPath
	log_removed "Git hooks path"
fi

# ── 4b. Addon teardown ──────────────────────
# Run each enabled addon's own uninstall.sh (if present) and remove enabled
# markers. With --purge also deletes local/addons/<id>/ config dirs.

ENABLED_ADDONS=()
if [ -d "${VAULT}/local/addons" ]; then
	for _marker in "${VAULT}/local/addons"/*/enabled; do
		[ -f "$_marker" ] || continue
		ENABLED_ADDONS+=("$(basename "$(dirname "$_marker")")")
	done
fi

if [ "${#ENABLED_ADDONS[@]}" -gt 0 ]; then
	echo "Tearing down ${#ENABLED_ADDONS[@]} enabled addon(s)…"
	for _addon_id in "${ENABLED_ADDONS[@]}"; do
		_addon_script="${VAULT}/system/addons/${_addon_id}/uninstall.sh"
		if [ -f "$_addon_script" ]; then
			bash "$_addon_script" 2>/dev/null || echo -e "${YELLOW}WARN${NC}  ${_addon_id}/uninstall.sh exited non-zero (continuing)" >&2
			log_removed "Addon ${_addon_id} (own uninstall.sh)"
		fi
		rm -f "${VAULT}/local/addons/${_addon_id}/enabled"
		log_removed "Addon enabled marker: ${_addon_id}"
		if [ "$PURGE_ADDON_CONFIGS" = true ] && [ -d "${VAULT}/local/addons/${_addon_id}" ]; then
			rm -rf "${VAULT}/local/addons/${_addon_id}"
			log_removed "Addon config dir: local/addons/${_addon_id}/ (--purge)"
		fi
	done
else
	log_skip "No enabled addons to tear down"
fi

# ── 4c. launchd cleanup (macOS only) ─────────
# Remove the main loop job and any per-addon scheduled jobs.

if [ "$(uname)" = "Darwin" ]; then
	_LOOP_LABEL="dev.agentbrain.loop"
	_LOOP_PLIST="${AGENT_HOME}/Library/LaunchAgents/${_LOOP_LABEL}.plist"
	# launchctl state is machine-global while AGENT_HOME may be a sandbox: only
	# consult launchctl for the real home, or a sandboxed uninstall would boot
	# out the user's LIVE loop job whose plist lives outside AGENT_HOME.
	if [ -f "$_LOOP_PLIST" ] || { [ "$AGENT_HOME" = "$HOME" ] && launchctl list 2>/dev/null | grep -q "$_LOOP_LABEL"; }; then
		launchctl bootout "gui/$(id -u)/${_LOOP_LABEL}" 2>/dev/null || true
		rm -f "$_LOOP_PLIST"
		log_removed "launchd job: ${_LOOP_LABEL}"
	else
		log_skip "launchd job: ${_LOOP_LABEL}"
	fi

	# Per-addon scheduled jobs: glob ALL local.agentbrain.*.plist files. Iterating
	# only enabled addons would miss a job whose addon was disabled after scheduling.
	for _addon_plist in "${AGENT_HOME}/Library/LaunchAgents"/local.agentbrain.*.plist; do
		[ -f "$_addon_plist" ] || continue
		_addon_label="$(basename "$_addon_plist" .plist)"
		_addon_id="${_addon_label#local.agentbrain.}"
		if ! bash "${VAULT}/scripts/setup-addon-launchd.sh" uninstall "$_addon_id" 2>/dev/null; then
			# Fallback for orphaned plists the addon tooling no longer knows about.
			launchctl bootout "gui/$(id -u)/${_addon_label}" 2>/dev/null || true
			rm -f "$_addon_plist"
		fi
		log_removed "launchd job: ${_addon_label}"
	done
fi

# ── 5. Summary ──────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Uninstall summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Removed: ${REMOVED}"
echo "  Skipped: ${SKIPPED}"
echo "  Checkout preserved: ${VAULT}"
echo ""
echo "  Left in place (uninstall never touches data or shared tooling):"
echo "    - Private vault:     ~/.agentBrain/vault (your knowledge, when local/ was shared)"
echo "    - Shared scope:      ~/.agentBrain/shared + its git remote (setup-shared-vault.sh)"
echo "    - Pi npm package:    @earendil-works/pi-coding-agent (npm uninstall -g to remove)"
echo "    - Runtimes:          nvm / bun / uv (install-prerequisites.sh)"
echo "    - Keychain entries:  pi-agent keychain and API keys (macOS Keychain)"
echo "    - Update config:     local/update/ (channel + auto_update settings)"
echo ""

# ── 6. Optional checkout removal ─────────────

# Deleting the checkout requires the explicit --delete-checkout flag (never implied by
# --yes). Even then, confirm once unless --yes was also given.
if [[ "$DELETE_CHECKOUT" == true ]] && confirm "Delete the checkout at ${VAULT}? This cannot be undone."; then
	rm -rf "$VAULT"
	echo -e "${RED}Deleted${NC}  checkout: ${VAULT}"
else
	echo "Checkout preserved at: ${VAULT}"
	[[ "$DELETE_CHECKOUT" != true ]] && echo "  (pass --delete-checkout to remove it too)"
fi

echo ""
echo "Done. Re-run 'bash scripts/setup.sh' to reinstall if needed."
