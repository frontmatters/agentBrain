#!/usr/bin/env bash
# ask_or_forward.sh — resolve a setup/onboard question via the 3-tier contract.
# Tier 0 (auto): env AGENTBRAIN_<KEY> or, when on a TTY, an interactive prompt.
# Tier 1 (skip): non-essential + non-interactive -> print default, log a note.
# Tier 2 (forward): essential + unanswerable here -> return 2 (Fase 2 wires the
#   event-bus forward; this phase signals the caller instead of deciding silently).
# Usage: ask_or_forward <key> <prompt> [default] [severity=optional|essential]
# Prints the resolved value to stdout; notes go to stderr.
ask_or_forward() {
	local key="$1" prompt="$2" default="${3:-}" severity="${4:-optional}"
	local envvar; envvar="AGENTBRAIN_$(printf '%s' "$key" | tr '[:lower:]-' '[:upper:]_')"
	# Tier 0: explicit env
	if [ -n "${!envvar:-}" ]; then printf '%s\n' "${!envvar}"; return 0; fi
	# Tier 0: interactive
	if [ -t 0 ]; then
		local ans; read -r -p "$prompt [${default}] " ans
		printf '%s\n' "${ans:-$default}"; return 0
	fi
	# Non-interactive
	if [ "$severity" = essential ]; then
		printf 'ask_or_forward: %s needs an answer (Tier 2 forward — not wired in Fase 1)\n' "$key" >&2
		return 2
	fi
	printf 'ask_or_forward: SKIP %s (non-interactive, used default=%s)\n' "$key" "$default" >&2
	printf '%s\n' "$default"; return 0
}
