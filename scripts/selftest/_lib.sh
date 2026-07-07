#!/usr/bin/env bash
# Shared helpers for the agent-agnostic selftest dispatcher.
# Sourced by scripts/selftest.sh and each scripts/selftest/<agent>.sh module.
#
# Counters (pass/fail/warn) live in the dispatcher's shell scope; the helpers
# (ok/nok/wrn) mutate them in-place via name references. Bash 3-compatible: no
# associative arrays, no `local -n` — just plain shell variables.

# Initialised by the dispatcher before any agent runs.
: "${pass:=0}"
: "${fail:=0}"
: "${warn:=0}"

ok()    { printf "  \033[32m✓\033[0m %s\n" "$1"; pass=$((pass+1)); }
nok()   { printf "  \033[31m✗\033[0m %s\n" "$1"; fail=$((fail+1)); }
wrn()   { printf "  \033[33m⚠\033[0m %s\n" "$1"; warn=$((warn+1)); }
hdr()   { printf "\n\033[1m▶ %s\033[0m\n" "$1"; }
note()  { printf "    \033[2m%s\033[0m\n" "$1"; }

# Agent-not-detected message — printed inline by the dispatcher so the user sees
# explicitly which sections were skipped (transparency over silent skipping).
skip_agent() {
	printf "\n  \033[2m∅ %s — %s\033[0m\n" "$1" "${2:-not detected}"
}

# Detect whether an agent module exposes a function. Used by the dispatcher to
# gracefully handle modules that only define `detect_<id>` or `run_<id>`.
has_fn() {
	declare -f "$1" >/dev/null 2>&1
}
