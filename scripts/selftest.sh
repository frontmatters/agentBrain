#!/usr/bin/env bash
# Selftest dispatcher — agent-agnostic.
# Runs the generic framework checks (always) plus one section per detected agent.
# Modules live in scripts/selftest/<agent>.sh and expose detect_<id> + run_<id>.
#
# Non-destructive: reads configuration, checks symlinks, performs ONE write/delete
# cycle in the Claude Code memory-redirect end-to-end test. No side effects on
# your real memory or journal.
#
# Locale: auto-detected from $LANG, override with AGENTBRAIN_LOCALE=nl|en.
#
# Usage:
#   bash scripts/selftest.sh              # full run
#   bash scripts/selftest.sh --only=claude_code,pi   # restrict to specific agents
#   bash scripts/selftest.sh --list       # list available agent modules
#
# Exit: 0 if no failures, 1 otherwise.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # BRAIN_ROOT is consumed by sourced agent modules below
BRAIN_ROOT="$(cd "$HERE/.." && pwd)"
export BRAIN_ROOT
SELFTEST_DIR="$HERE/selftest"

# i18n
# shellcheck source=lib/_strings.sh
# shellcheck disable=SC1091
source "$HERE/lib/_strings.sh"

# Counters live here so module helpers mutate them in-place.
pass=0
fail=0
warn=0

# Shared helpers (ok/nok/wrn/hdr/note/skip_agent/has_fn).
# shellcheck source=selftest/_lib.sh
# shellcheck disable=SC1091
source "$SELFTEST_DIR/_lib.sh"

# Agent registry — order = display order. Same shape as
# scripts/setup-agent-integrations.sh: "<module>:<display name>".
# To add a new agent: drop scripts/selftest/<module>.sh and append a row here.
AGENT_MODULES=(
	"claude-code:Claude Code"
	"pi:Pi"
	"copilot-cli:GitHub Copilot CLI"
	"gemini-cli:Gemini CLI"
)

# ── flags ─────────────────────────────────────────────────────
only_filter=""
list_only=false
for arg in "$@"; do
	case "$arg" in
		--list) list_only=true ;;
		--only=*) only_filter="${arg#--only=}" ;;
		-h|--help)
			sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
	esac
done

if $list_only; then
	printf "%-20s %s\n" "module" "display name"
	for entry in "${AGENT_MODULES[@]}"; do
		IFS=':' read -r mod name <<<"$entry"
		printf "%-20s %s\n" "$mod" "$name"
	done
	exit 0
fi

# ── generic (always) ──────────────────────────────────────────
# shellcheck source=selftest/generic.sh
# shellcheck disable=SC1091
source "$SELFTEST_DIR/generic.sh"
run_generic

# ── per-agent ─────────────────────────────────────────────────
in_filter() {
	[[ -z "$only_filter" ]] && return 0
	local IFS=','
	for f in $only_filter; do
		[[ "$f" == "$1" ]] && return 0
	done
	return 1
}

for entry in "${AGENT_MODULES[@]}"; do
	IFS=':' read -r module display_name <<<"$entry"
	in_filter "$module" || continue

	module_file="$SELFTEST_DIR/${module}.sh"
	if [[ ! -f "$module_file" ]]; then
		skip_agent "$display_name" "module file not found: $module_file"
		continue
	fi

	# Use a fresh subshell-free source so counter mutations persist.
	# shellcheck source=/dev/null  # module path is computed at runtime
	source "$module_file"

	# Convert module-id to function suffix: dashes → underscores.
	fn_suffix="${module//-/_}"

	if has_fn "detect_$fn_suffix"; then
		if "detect_$fn_suffix"; then
			"run_$fn_suffix"
		else
			skip_agent "$display_name" "$(t selftest.agent.not_detected)"
		fi
	else
		skip_agent "$display_name" "detect_$fn_suffix() not defined"
	fi
done

# ── summary ───────────────────────────────────────────────────
hdr "$(t generic.summary)"
printf "  locale: \033[36m%s\033[0m   %s: \033[32m%d\033[0m   %s: \033[31m%d\033[0m   %s: \033[33m%d\033[0m\n" \
	"$_AGENTBRAIN_LOCALE" "$(t generic.passed)" "$pass" "$(t generic.failed)" "$fail" "$(t generic.warnings)" "$warn"

if (( fail == 0 )); then
	printf "\n  \033[32m▣ %s\033[0m %s\n\n" "$(t selftest.summary.all_good)" "$(t selftest.summary.all_good_hint)"
	exit 0
else
	printf "\n  \033[31m▣ %s\033[0m\n\n" "$(t selftest.summary.failures)"
	exit 1
fi
