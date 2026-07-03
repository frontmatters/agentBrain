#!/usr/bin/env bash
# Gemini CLI — pointer in ~/.gemini/GEMINI.md.

detect_gemini_cli() {
	command -v gemini &>/dev/null || [[ -d "$HOME/.gemini" ]]
}

run_gemini_cli() {
	hdr "Gemini CLI"

	local POINTER="$HOME/.gemini/GEMINI.md"
	if [[ -f "$POINTER" ]]; then
		ok "$(t selftest.gemini.pointer_present) $POINTER"
		if grep -q "agentBrain" "$POINTER" 2>/dev/null; then
			ok "$(t selftest.gemini.pointer_links_brain)"
		else
			wrn "$(t selftest.gemini.pointer_no_brain_ref)"
		fi
	else
		nok "$(t selftest.gemini.pointer_missing) $POINTER"
	fi
}
