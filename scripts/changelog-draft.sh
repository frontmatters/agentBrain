#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# changelog-draft.sh — draft the [Unreleased] section from conventional commits.
# The ksc synergy: Conventional Commits make Keep-a-Changelog generatable —
# feat->Added, fix->Fixed, refactor/chore/docs->Changed, revert->Removed.
# Prints a draft to stdout; paste/curate it under ## [Unreleased] in CHANGELOG.md.
# Usage: bash scripts/changelog-draft.sh [<since-ref>]   (default: latest v* tag)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
SINCE="${1:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null)}"
[ -n "$SINCE" ] || { echo "no tag found — pass a since-ref" >&2; exit 1; }
echo "<!-- draft from $SINCE..HEAD ($(git rev-list --count "$SINCE"..HEAD) commits) — curate before committing -->"
section() {
	local title="$1"; shift
	local out; out="$(git log --no-merges --pretty='- %s' "$SINCE"..HEAD | grep -E "$1" | sed -E 's/^- [a-z]+(\([^)]*\))?!?: /- /')"
	[ -n "$out" ] && printf '\n### %s\n\n%s\n' "$title" "$out"
}
section "Added"   '^- feat'
section "Fixed"   '^- fix'
section "Changed" '^- (refactor|perf|docs|chore|style|build|ci|test)'
section "Removed" '^- revert'
