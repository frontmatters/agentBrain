#!/usr/bin/env bash
# setup-skills.sh — Install the brain's skills into each detected agent's native skills dir,
# so every agent gets the same skills (not just a text index). One source, many connectors.
#
# Sources (both, alias-aware so `brain use dev|live` flips them):
#   - public framework skills: <brain>/system/skills/<name>/SKILL.md
#   - private personal skills:  <brain>/local/skills/<name>/SKILL.md
# Targets (only the agents whose config dir exists):
#   - Claude Code:  ~/.claude/skills/<name>
#   - Copilot CLI:  ~/.copilot/skills/<name>
# Pi is handled by configure-pi.sh (its own skills dir + ignore list).
# Safe to re-run (idempotent; NOTE: prunes skill links whose source no longer exists).
#
# Safety: only ever creates/removes symlinks that point INTO the brain. A pre-existing
# entry that is NOT a brain symlink is left untouched (never clobber the user's own skill).
# Safe to re-run (idempotent).

set -euo pipefail

VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"
BRAIN="${BRAIN_ALIAS:-$AGENT_HOME/agentBrain}"
# Where addons.sh records enabled-state; an addon's skill is linked only while enabled.
STATE="${ADDONS_STATE:-$VAULT/local/addons}"

# Shared addon-skill linking — one source of truth with configure-pi.sh (Pi).
# shellcheck disable=SC1091  # dynamic source path; lib/skills.sh is shellcheck-clean on its own
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/skills.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# link_skills_into <agent-skills-dir> <source-root> <source-label>
link_skills_into() {
	local dest_dir="$1" src_root="$2" label="$3"
	[ -d "$src_root" ] || return 0
	mkdir -p "$dest_dir"
	local added=0
	for src in "$src_root"/*/; do
		[ -f "${src}SKILL.md" ] || continue
		local name target
		name="$(basename "$src")"
		target="$dest_dir/$name"
		if [ -e "$target" ] && ! skilllib_is_brain_link "$target"; then
			echo -e "  ${YELLOW}keep${NC}  ${name} (existing non-brain skill — left untouched)"
			continue
		fi
		ln -sfn "${BRAIN}/${label}/${name}" "$target"
		added=$((added + 1))
	done
	[ "$added" -gt 0 ] && echo -e "  ${GREEN}✓${NC} ${added} skills -> ${dest_dir}"
	return 0
}

# Remove orphaned brain-skill symlinks: the source skill was deleted from the brain.
# Keeps each agent's dir in sync with the brain. Only brain symlinks are ever touched.
prune_orphaned() {
	local dest_dir="$1"
	[ -d "$dest_dir" ] || return 0
	local link name
	for link in "$dest_dir"/*; do
		skilllib_is_brain_link "$link" || continue
		name="$(basename "$link")"
		if [ ! -f "$VAULT/system/skills/$name/SKILL.md" ] && [ ! -f "$VAULT/local/skills/$name/SKILL.md" ]; then
			rm -f "$link"
			echo -e "  ${YELLOW}–${NC} removed ${name} (no longer in the brain)"
		fi
	done
}

install_for_agent() {
	local dest_dir="$1" agent_label="$2"
	echo -e "${CYAN}${agent_label}${NC}"
	link_skills_into "$dest_dir" "$VAULT/system/skills" "system/skills"
	link_skills_into "$dest_dir" "$VAULT/local/skills" "local/skills"
	prune_orphaned "$dest_dir"
	skilllib_sync_addon_skills "$dest_dir" "$VAULT/system/addons" "$STATE" "$BRAIN"
}

# Lighter per-agent pass used by `addons.sh enable/disable`: only (re)syncs the
# addon-provided skills, leaving standalone skill links untouched.
sync_addons_for_agent() {
	local dest_dir="$1" agent_label="$2"
	echo -e "${CYAN}${agent_label}${NC}"
	skilllib_sync_addon_skills "$dest_dir" "$VAULT/system/addons" "$STATE" "$BRAIN"
}

# Mode: default re-syncs every skill; `sync-addons` only re-syncs addon skills
# (used by `addons.sh enable/disable`, which change only enabled-state).
MODE="${1:-all}"

echo ""
if [ "$MODE" = "sync-addons" ]; then
	echo -e "${CYAN}Syncing addon skills into detected agents...${NC}"
else
	echo -e "${CYAN}Installing brain skills into detected agents...${NC}"
fi

# Table: "<detect-dir>|<detect-cmd>|<skills-dir>|<label>"
# detect-dir: non-empty → check if directory exists; detect-cmd: non-empty → check if command found.
# An agent is installed when either condition holds (OR logic).
AGENTS=(
	"${AGENT_HOME}/.claude||${AGENT_HOME}/.claude/skills|Claude Code"
	"${AGENT_HOME}/.copilot|copilot|${AGENT_HOME}/.copilot/skills|Copilot CLI"
)

for _entry in "${AGENTS[@]}"; do
	IFS='|' read -r _det_dir _det_cmd _skills_dir _label <<< "$_entry"
	_detected=false
	[ -n "$_det_dir" ] && [ -d "$_det_dir" ] && _detected=true
	[ -n "$_det_cmd" ] && command -v "$_det_cmd" &>/dev/null && _detected=true
	if "$_detected"; then
		if [ "$MODE" = "sync-addons" ]; then
			sync_addons_for_agent "$_skills_dir" "$_label"
		else
			install_for_agent "$_skills_dir" "$_label"
		fi
	fi
done
