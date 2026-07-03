#!/usr/bin/env bash
# Pi agent — checks the Pi-specific integration: extensions + skills symlinked
# from system/pi-config/ into ~/.pi/agent/, tsconfig present, brain pointer.

detect_pi() {
	command -v pi &>/dev/null || [[ -d "$HOME/.pi" ]]
}

run_pi() {
	hdr "Pi"

	# CLI / install
	if command -v pi &>/dev/null; then
		ok "$(t selftest.pi.cli_present)"
	else
		wrn "$(t selftest.pi.cli_missing)"
	fi

	# Pi config dir
	local PI_HOME="$HOME/.pi"
	if [[ -d "$PI_HOME" ]]; then
		ok "$(t selftest.pi.home_present) $PI_HOME"
	else
		nok "$(t selftest.pi.home_missing) $PI_HOME"
		return
	fi

	# Extensions: symlinked into ~/.pi/agent/extensions/
	local ext_dir="$PI_HOME/agent/extensions"
	local ext_source="$BRAIN_ROOT/system/pi-config/extensions"
	if [[ -d "$ext_dir" ]]; then
		local linked=0 missing=0 e
		for e in "$ext_source"/*.ts "$ext_source"/*/index.ts; do
			[[ -f "$e" ]] || continue
			local name; name="$(basename "$(dirname "$e")")"
			[[ "$name" == "extensions" ]] && name="$(basename "$e" .ts)"
			if [[ -L "$ext_dir/$name" ]] || [[ -L "$ext_dir/$name.ts" ]] || [[ -e "$ext_dir/$name" ]]; then
				linked=$((linked+1))
			else
				missing=$((missing+1))
			fi
		done
		if (( missing == 0 )); then
			ok "$(t selftest.pi.extensions_linked) ($linked)"
		else
			wrn "$(t selftest.pi.extensions_partial) ($linked linked, $missing missing)"
		fi
	else
		wrn "$(t selftest.pi.extensions_dir_missing) $ext_dir"
	fi

	# Skills: symlinked into ~/.pi/agent/skills/
	local skills_dir="$PI_HOME/agent/skills"
	if [[ -d "$skills_dir" ]]; then
		local skill_count; skill_count="$(find "$skills_dir" -maxdepth 1 -mindepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')"
		if (( skill_count > 0 )); then
			ok "$(t selftest.pi.skills_linked) ($skill_count)"
		else
			wrn "$(t selftest.pi.skills_empty)"
		fi
	else
		wrn "$(t selftest.pi.skills_dir_missing) $skills_dir"
	fi

	# tsconfig
	if [[ -f "$PI_HOME/agent/tsconfig.json" ]]; then
		ok "$(t selftest.pi.tsconfig_present)"
	else
		wrn "$(t selftest.pi.tsconfig_missing)"
	fi
}
