#!/usr/bin/env bash
# lib/skills.sh — shared addon-skill linking, sourced by setup-skills.sh (Claude
# Code + Copilot CLI) and configure-pi.sh (Pi). Single source of truth so the
# agents can never diverge on how an enabled addon's SKILL.md becomes a usable
# skill. Pure helpers: every root is passed in, no globals, no stdout.

# A symlink is "ours" when it resolves into the brain's skill trees or an addon.
skilllib_is_brain_link() {
	local link="$1" target
	[ -L "$link" ] || return 1
	target="$(readlink "$link")"
	[[ "$target" == *"/system/skills/"* || "$target" == *"/local/skills/"* || "$target" == *"/system/addons/"* ]]
}

# skilllib_sync_addon_skills <dest_dir> <addons_root> <state_root> <brain_root>
#   dest_dir    agent skills dir (e.g. ~/.claude/skills, ~/.pi/agent/skills)
#   addons_root <brain>/system/addons
#   state_root  where enabled-markers live (<brain>/local/addons or $ADDONS_STATE)
#   brain_root  symlink-target prefix (the stable brain alias)
#
# Links each ENABLED addon's SKILL.md into <dest_dir>/<id>/SKILL.md (the file, not
# the whole addon dir, so manifest/README/bin never leak in), and prunes any
# addon-skill link whose addon is now disabled or gone. Never clobbers a user's
# own (non-brain) skill of the same id. Idempotent.
skilllib_sync_addon_skills() {
	local dest_dir="$1" addons_root="$2" state_root="$3" brain_root="$4"
	[ -d "$addons_root" ] || return 0
	mkdir -p "$dest_dir"

	local src id target
	for src in "$addons_root"/*/; do
		[ -f "${src}SKILL.md" ] || continue
		id="$(basename "$src")"
		[ -f "$state_root/$id/enabled" ] || continue
		target="$dest_dir/$id/SKILL.md"
		# Present but not one of ours -> a user's own skill; hands off.
		if [ -e "$target" ] && ! skilllib_is_brain_link "$target"; then
			continue
		fi
		mkdir -p "$dest_dir/$id"
		ln -sfn "${brain_root}/system/addons/${id}/SKILL.md" "$target"
	done

	# Prune addon-skill links whose addon was disabled or removed.
	local entry skill name
	for entry in "$dest_dir"/*/; do
		skill="${entry}SKILL.md"
		[ -L "$skill" ] || continue
		case "$(readlink "$skill")" in *"/system/addons/"*) : ;; *) continue ;; esac
		name="$(basename "$entry")"
		if [ ! -f "$addons_root/$name/SKILL.md" ] || [ ! -f "$state_root/$name/enabled" ]; then
			rm -f "$skill"
			rmdir "$entry" 2>/dev/null || true
		fi
	done
}
