#!/usr/bin/env bash
# GitHub Copilot CLI — pointer in ~/.copilot/copilot-instructions.md + skills dir.

detect_copilot_cli() {
	command -v copilot &>/dev/null || [[ -d "$HOME/.copilot" ]]
}

run_copilot_cli() {
	hdr "GitHub Copilot CLI"

	local POINTER="$HOME/.copilot/copilot-instructions.md"
	if [[ -f "$POINTER" ]]; then
		ok "$(t selftest.copilot.pointer_present) $POINTER"
		if grep -q "agentBrain" "$POINTER" 2>/dev/null; then
			ok "$(t selftest.copilot.pointer_links_brain)"
		else
			wrn "$(t selftest.copilot.pointer_no_brain_ref)"
		fi
	else
		nok "$(t selftest.copilot.pointer_missing) $POINTER"
	fi

	# Skills dir — copilot CLI reads .github/skills/ symlinked or .copilot/skills/
	local skills_dir="$HOME/.copilot/skills"
	if [[ -d "$skills_dir" ]]; then
		local skill_count; skill_count="$(find "$skills_dir" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
		if (( skill_count > 0 )); then
			ok "$(t selftest.copilot.skills_present) ($skill_count)"
		else
			wrn "$(t selftest.copilot.skills_empty)"
		fi
	else
		note "$(t selftest.copilot.skills_dir_absent)"
	fi
}
