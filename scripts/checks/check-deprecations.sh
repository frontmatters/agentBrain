#!/usr/bin/env bash
# check-deprecations.sh — health of the deprecation mechanism across agentBrain.
#
# Scans every frontmatter-carrying artifact that can carry a `deprecated:` block,
# validates its shape, and flags OVERDUE ones (today > remove_after). Doctor-wired.
#
# Design: WARN on overdue (never hard-fail) so a missed removal nags every doctor
# run without blocking unrelated work; FAIL only on a malformed block. The block
# shape is documented in system/addons/README.md (### Deprecation).
#
# EXTENDING TO OTHER PARTS OF agentBrain: add a glob to SCAN_GLOBS below. Any
# artifact whose file starts with a `---` frontmatter block works as-is —
# agent-config, pi-config, templates, explainer themes, etc. Non-frontmatter
# artifacts (shell scripts, CLI subcommand names, MCP tool names, shorthands)
# are NOT covered here; those need a runtime deprecation warning at their own
# entrypoint (print "deprecated → use X" to stderr when the old name is used).
set -euo pipefail
shopt -s nullglob

# Run from the repo root (as doctor does). Globs are relative to CWD; local/ may
# be a symlink to the shared vault — that resolves transparently.
SCAN_GLOBS=(
	system/addons/*/manifest.md          # addons
	system/skills/*/SKILL.md             # system skills
	vault/skills/*/SKILL.md              # private/local skills
	# --- extend here (frontmatter artifacts only) ---
	# system/agent-config/*.md
	# system/pi-config/extensions/*/manifest.md
	# system/explainers/themes/*/theme.md
)

VALID_REASON=(renamed replaced merged discontinued)
TODAY="$(date +%Y-%m-%d)"

dep_sub() { awk -v k="$2" '/^---[[:space:]]*$/{fm++;next} fm==1&&/^deprecated:[[:space:]]*$/{s=1;next} fm==1&&s&&/^[^[:space:]]/{s=0} fm==1&&s&&$0 ~ "^[[:space:]]+"k":"{sub("^[[:space:]]+"k":[[:space:]]*","");sub(/[[:space:]]*#.*$/,"");gsub(/"/,"");print;exit}' "$1"; }
has_dep() { grep -qE "^deprecated:[[:space:]]*$" "$1"; }
in_set()  { local x="$1"; shift; for v in "$@"; do [ "$x" = "$v" ] && return 0; done; return 1; }

errors=0 warns=0 active=0

for g in "${SCAN_GLOBS[@]}"; do
	for f in $g; do
		[ -f "$f" ] || continue
		has_dep "$f" || continue
		reason="$(dep_sub "$f" reason)"
		repl="$(dep_sub "$f" replaced_by)"
		rem="$(dep_sub "$f" remove_after)"
		# --- shape validation ---
		if [ -z "$reason" ]; then
			echo "FAIL $f: deprecated block missing required 'reason'" >&2; errors=$((errors+1)); continue
		elif ! in_set "$reason" "${VALID_REASON[@]}"; then
			echo "FAIL $f: invalid deprecated.reason '$reason' (use: ${VALID_REASON[*]})" >&2; errors=$((errors+1)); continue
		fi
		if [ "$reason" != "discontinued" ] && [ -z "$repl" ]; then
			echo "FAIL $f: deprecated.replaced_by required unless reason=discontinued" >&2; errors=$((errors+1)); continue
		fi
		active=$((active+1))
		target="${repl:+ → $repl}"
		# --- overdue check (lexicographic on ISO dates is correct ordering) ---
		if [ -n "$rem" ] && [[ "$TODAY" > "$rem" ]]; then
			echo "WARN $f: OVERDUE — remove_after ${rem} has passed; decommission this deprecated alias${target}" >&2
			warns=$((warns+1))
		else
			printf '  · %s (%s)%s%s\n' "$f" "$reason" "$target" "${rem:+, removed after $rem}"
		fi
	done
done

if [ "$active" -eq 0 ] && [ "$errors" -eq 0 ]; then
	echo "check-deprecations: no deprecated artifacts"
	exit 0
fi
echo "check-deprecations: ${active} active, ${warns} overdue, ${errors} error(s)"
[ "$errors" -eq 0 ] || exit 1
exit 0
