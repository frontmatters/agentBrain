#!/usr/bin/env bash
# check-skills-index.sh — Enforce skills-index parity.
# Rule: system/skills.md is the thin index of system/skills/ — every skill directory
# has exactly one table row (matched on the skill name in the first column), and every
# table row points at an existing skill directory. Without this check the index drifts
# into lies (it silently missed ~18 of 39 skills once). Addon-/script-provided commands
# (/journal, /selftest) live in prose below the table, not as rows, so they are exempt
# by construction. `_shared/` is helper material, not a skill.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

INDEX="system/skills.md"
SKILLS_DIR="system/skills"
errors=0

if [ ! -f "$INDEX" ] || [ ! -d "$SKILLS_DIR" ]; then
	echo "check-skills-index: $INDEX or $SKILLS_DIR/ missing" >&2
	exit 1
fi

# Skill names from the index: first table column, rows shaped `| \`/name\` | ... |`.
# shellcheck disable=SC2016  # single quotes are intentional: sed pattern, not shell expansion
index_names="$(grep -E '^\| `/' "$INDEX" | sed -E 's#^\| `/([^`]+)`.*#\1#' | sort)"

# Skill names from the filesystem: one directory per skill (skip _shared helpers).
dir_names="$(
	for d in "$SKILLS_DIR"/*/; do
		[ -d "$d" ] || continue
		name="$(basename "$d")"
		[ "$name" = "_shared" ] && continue
		echo "$name"
	done | sort
)"

# Direction 1: every skill directory has an index row.
while IFS= read -r name; do
	[ -n "$name" ] || continue
	if ! grep -qx "$name" <<<"$index_names"; then
		echo "FAIL $SKILLS_DIR/$name/ has no row in $INDEX — add \`/$name\` to the table" >&2
		errors=$((errors + 1))
	fi
done <<<"$dir_names"

# Direction 2: every index row has a skill directory.
while IFS= read -r name; do
	[ -n "$name" ] || continue
	if ! grep -qx "$name" <<<"$dir_names"; then
		echo "FAIL $INDEX lists \`/$name\` but $SKILLS_DIR/$name/ does not exist — remove the row or add the skill" >&2
		errors=$((errors + 1))
	fi
done <<<"$index_names"

if [ "$errors" -gt 0 ]; then
	echo "check-skills-index: $errors drift issue(s) between $SKILLS_DIR/ and $INDEX" >&2
	exit 1
fi
echo "check-skills-index: $(wc -l <<<"$dir_names" | tr -d ' ') skills, index and directories in parity"
