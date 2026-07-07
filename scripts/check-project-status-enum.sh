#!/usr/bin/env bash
# Validate `status:` frontmatter values in local/projects/*/index.md against
# the canonical enum. Catches drift like `status: unknown` or free-text values
# such as `status: phase-3-shipped` that bypass the project-update skill spec
# and confuse /list-parks filtering.
#
# Canonical enum (5 values):
#   active     — actively being worked on
#   paused     — temporarily on hold (shows in /list-parks)
#   blocked    — externally blocked (shows in /list-parks)
#   done       — completed
#   abandoned  — definitively dropped (rare cleanup outcome)
#
# Phase-info like "phase-3-shipped" belongs in the ## Status body or a
# separate `phase:` frontmatter field, NOT in `status:`.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECTS_DIR="local/projects"

if [ ! -d "$PROJECTS_DIR" ]; then
	printf 'check-project-status-enum: %s not found, nothing to check.\n' "$PROJECTS_DIR"
	exit 0
fi

# Enum as a pipe-separated regex alternation. Anchored in the grep below.
VALID_PATTERN='^status: (active|paused|blocked|done|abandoned)[[:space:]]*$'

bad=()
missing=()

while IFS= read -r idx; do
	# Extract the first `status:` line from frontmatter (top of file).
	# Use a small head window so we don't accidentally match body text.
	status_line=$(head -30 "$idx" | grep -E '^status:' | head -1 || true)

	if [ -z "$status_line" ]; then
		missing+=("$idx")
		continue
	fi

	if ! echo "$status_line" | grep -qE "$VALID_PATTERN"; then
		# Strip "status: " prefix for the report
		bad_value=$(echo "$status_line" | sed -E 's/^status:[[:space:]]*//')
		bad+=("$idx → got '$bad_value'")
	fi
done < <(
	# Only project index.md files (one level deep under local/projects/<name>/index.md).
	# The top-level local/projects/index.md is a meta-registry (type: system), not a project.
	find "$PROJECTS_DIR" -mindepth 2 -maxdepth 2 -name 'index.md' |
	while IFS= read -r f; do
		# Defense in depth: only check files declaring type: project.
		if head -10 "$f" | grep -qE '^type: project[[:space:]]*$'; then
			echo "$f"
		fi
	done | sort
)

fail=0

if ((${#bad[@]} > 0)); then
	printf 'check-project-status-enum: %s invalid status value(s):\n' "${#bad[@]}" >&2
	printf '  ✗ %s\n' "${bad[@]}" >&2
	printf '\nValid values: active | paused | blocked | done | abandoned\n' >&2
	fail=1
fi

if ((${#missing[@]} > 0)); then
	printf 'check-project-status-enum: %s project(s) missing status field:\n' "${#missing[@]}" >&2
	printf '  ⚠ %s\n' "${missing[@]}" >&2
	fail=1
fi

if [ "$fail" -eq 0 ]; then
	count=$(find "$PROJECTS_DIR" -mindepth 2 -maxdepth 2 -name 'index.md' | wc -l | tr -d ' ')
	printf 'check-project-status-enum: %s project(s) all have valid status values.\n' "$count"
fi

exit "$fail"
