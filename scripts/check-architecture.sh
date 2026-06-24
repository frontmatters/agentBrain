#!/usr/bin/env bash
# check-architecture.sh — Guard system/architecture.md against path-drift.
# Structural checks (frontmatter/links) cannot verify that the prose describes reality.
# This verifies every repo-relative path the doc names (in backticks) actually exists.
# Scope: dir-qualified repo paths only (system/ scripts/ .github/ local/ templates/
# learnings/ projects/). Skips placeholders (<...>), globs (*), external (~) and
# qualified refs (:), and bare filenames (too ambiguous to resolve safely).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DOC="system/architecture.md"
if [ ! -f "$DOC" ]; then
	echo "check-architecture: $DOC missing" >&2
	exit 1
fi

errors=0
while IFS= read -r ref; do
	if [ ! -e "$ref" ]; then
		case "$ref" in
			# local/ is per-machine user runtime state, legitimately absent in a
			# fresh install (e.g. local/addons appears only once an addon is
			# installed). Documenting it in architecture.md must not fail doctor.
			local/*) continue ;;
			*) echo "FAIL architecture.md names a path that does not exist: $ref" >&2; errors=$((errors + 1)) ;;
		esac
	fi
done < <(
	# shellcheck disable=SC2016  # backticks are literal regex chars here, not command substitution
	grep -oE '`[^`]+`' "$DOC" | tr -d '`' |
		grep -E '^(system|scripts|local|templates|learnings|projects|\.github)/' |
		grep -vE '[*<>~:{}]' |   # skip globs, placeholders, external (~), qualified (:) and brace-shorthand
		sed -E 's#/+$##' |
		sort -u
)

# Skills-home invariant (architecture.md §5): the agnostic home is system/skills/;
# .github/skills/ may only hold symlinks into it, never the source itself — so skills
# cannot drift back into a vendor-specific directory.
if [ ! -d system/skills ]; then
	echo "FAIL system/skills/ (the agnostic skills home) is missing" >&2
	errors=$((errors + 1))
fi
if [ -d .github/skills ]; then
	for entry in .github/skills/*; do
		[ -e "$entry" ] || continue
		if [ ! -L "$entry" ]; then
			echo "FAIL $entry is not a symlink — skills live in system/skills/; .github/skills/ may only link in" >&2
			errors=$((errors + 1))
		fi
	done
fi

if [ "$errors" -gt 0 ]; then
	echo "check-architecture: $errors issue(s) in $DOC / skills layout — update the doc or the code" >&2
	exit 1
fi
echo "check-architecture: all repo paths named in $DOC exist; skills home is agnostic"
