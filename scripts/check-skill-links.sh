#!/usr/bin/env bash
# check-skill-links.sh — verify that every brain skill is actually installed
# (symlinked) into each detected agent's native skills dir, and that no
# orphaned/broken brain symlinks linger there.
#
# Closes the drift gap where a skill added to system/skills/ or local/skills/
# after install never becomes visible to agents because setup-skills.sh was
# not re-run (found 2026-06-11: brain-hide/forget skill set existed in the
# vault for a week but was invisible to Claude Code).
#
# Mirrors the agent table + brain-symlink boundary of setup-skills.sh:
# entries in an agent dir that are NOT brain symlinks belong to the user and
# are never flagged (setup-skills.sh leaves them untouched too).
#
# Local-only check (agent dirs are machine state, absent in CI).
# Exit codes: 0 ok, 1 drift found. Repair: bash scripts/setup-skills.sh
#
# Bash 3.2 compatible.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# VAULT/STATE default to the real repo in production; tests override them to point
# at a temp registry. Keeps this check in lockstep with setup-skills.sh.
VAULT="${VAULT:-$ROOT_DIR}"
STATE="${ADDONS_STATE:-$VAULT/local/addons}"
AGENT_HOME="${AGENTBRAIN_HOME:-$HOME}"

addon_enabled() { [ -f "$STATE/$1/enabled" ]; }

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

# Same boundary as setup-skills.sh: a symlink is "ours" when it resolves
# into the brain's skills trees.
is_brain_skill_link() {
	local link="$1" target
	[ -L "$link" ] || return 1
	target="$(readlink "$link")"
	[[ "$target" == *"/system/skills/"* || "$target" == *"/local/skills/"* ]]
}

check_agent() {
	local skills_dir="$1" label="$2"
	echo "check-skill-links: ${label} (${skills_dir})"

	if [ ! -d "$skills_dir" ]; then
		bad "skills dir missing — run: bash scripts/setup-skills.sh"
		return
	fi

	# 1. Every vault skill must be linked (or shadowed by a user's own skill).
	local src_root src name target
	for src_root in "$VAULT/system/skills" "$VAULT/local/skills"; do
		[ -d "$src_root" ] || continue
		for src in "$src_root"/*/; do
			[ -f "${src}SKILL.md" ] || continue
			name="$(basename "$src")"
			target="$skills_dir/$name"
			if [ -e "$target" ] || [ -L "$target" ]; then
				ok
			else
				bad "$name not installed for ${label} — run: bash scripts/setup-skills.sh"
			fi
		done
	done

	# 1b. Every ENABLED addon that ships a SKILL.md must be linked as well.
	if [ -d "$VAULT/system/addons" ]; then
		for src in "$VAULT/system/addons"/*/; do
			[ -f "${src}SKILL.md" ] || continue
			name="$(basename "$src")"
			addon_enabled "$name" || continue
			target="$skills_dir/$name/SKILL.md"
			if [ -e "$target" ] || [ -L "$target" ]; then
				ok
			else
				bad "addon skill $name not installed for ${label} — run: bash scripts/setup-skills.sh"
			fi
		done
	fi

	# 2. No orphaned or broken brain symlinks left behind.
	local link
	for link in "$skills_dir"/*; do
		is_brain_skill_link "$link" || continue
		name="$(basename "$link")"
		if [ ! -f "$VAULT/system/skills/$name/SKILL.md" ] && [ ! -f "$VAULT/local/skills/$name/SKILL.md" ]; then
			bad "orphaned brain symlink: $name (source gone) — run: bash scripts/setup-skills.sh"
		elif [ ! -e "$link" ]; then
			bad "broken symlink: $name -> $(readlink "$link")"
		else
			ok
		fi
	done

	# 2b. No stale addon-skill links: the addon was disabled or its SKILL.md is gone.
	local entry skill
	for entry in "$skills_dir"/*/; do
		skill="${entry}SKILL.md"
		[ -L "$skill" ] || continue
		case "$(readlink "$skill")" in *"/system/addons/"*) : ;; *) continue ;; esac
		name="$(basename "$entry")"
		if [ ! -f "$VAULT/system/addons/$name/SKILL.md" ] || ! addon_enabled "$name"; then
			bad "stale addon skill link: $name (disabled or removed) — run: bash scripts/setup-skills.sh"
		elif [ ! -e "$skill" ]; then
			bad "broken addon skill link: $name -> $(readlink "$skill")"
		else
			ok
		fi
	done
}

# Detection table ("<detect-dir>|<detect-cmd>|<skills-dir>|<label>"). Claude Code +
# Copilot are wired by setup-skills.sh; Pi by configure-pi.sh — all three now link
# the SAME standalone skills (system/skills + local/skills) + enabled-addon SKILLs,
# so the parity check below applies uniformly. Pi is detected by its config dir
# only (empty detect-cmd): a present `pi` binary must not flag a host whose
# ~/.pi/agent was never created (e.g. test temp homes).
AGENTS=(
	"${AGENT_HOME}/.claude||${AGENT_HOME}/.claude/skills|Claude Code"
	"${AGENT_HOME}/.copilot|copilot|${AGENT_HOME}/.copilot/skills|Copilot CLI"
	"${AGENT_HOME}/.pi/agent||${AGENT_HOME}/.pi/agent/skills|Pi"
)

detected=0
for _entry in "${AGENTS[@]}"; do
	IFS='|' read -r _det_dir _det_cmd _skills_dir _label <<< "$_entry"
	_detected=false
	[ -n "$_det_dir" ] && [ -d "$_det_dir" ] && _detected=true
	[ -n "$_det_cmd" ] && command -v "$_det_cmd" &>/dev/null && _detected=true
	if "$_detected"; then
		detected=$((detected + 1))
		check_agent "$_skills_dir" "$_label"
	fi
done

if [ "$detected" -eq 0 ]; then
	echo "check-skill-links: no agents detected — skipping"
	exit 0
fi

echo "check-skill-links: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
