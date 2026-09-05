#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# changes.sh — one-screen drift report: what changed, where, what needs a
# merge and what needs a bump. Read-only; never blocks anything. Runs as the
# pre-flight of sync-agentbrain-local.sh and standalone.
#
# Usage: scripts/changes.sh [repo-path ...]
#   without args: the vault repo + known sibling repos that exist
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPOS=("$@")
if [ ${#REPOS[@]} -eq 0 ]; then
	REPOS=("$ROOT_DIR")
	[ -d "$HOME/Developer/agentBrain-harness/agentbrain-src/.git" ] && REPOS+=("$HOME/Developer/agentBrain-harness/agentbrain-src")
fi

export GIT_TERMINAL_PROMPT=0

fail=0
for repo in "${REPOS[@]}"; do
	name="$(basename "$repo")"
	echo "== $name =="
	if [ ! -d "$repo/.git" ] && ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
		echo "   (no git repo, skipping)"; continue
	fi

	branch="$(git -C "$repo" branch --show-current)"
	echo "   branch: ${branch:-detached}"

	# Dirty files, grouped by top two path segments so a mixed tree shows itself.
	tracked="$(git -C "$repo" status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
	untracked="$(git -C "$repo" status --porcelain | grep -c '^??' || true)"
	if [ "$tracked" -gt 0 ] || [ "$untracked" -gt 0 ]; then
		echo "   modified (tracked): $tracked · untracked: $untracked"
		git -C "$repo" status --porcelain | awk '{ $1=""; sub(/^ /,""); print }' \
			| cut -d/ -f1-2 | sort | uniq -c | sort -rn | head -5 \
			| sed 's/^/     /'
		if [ $((tracked + untracked)) -ge 10 ]; then
			echo "   ⚠ large working tree: split by task before committing"
			fail=1
		fi
	else
		echo "   dirty: clean"
	fi

	# Ahead/behind vs main (or master). Fetch is best-effort: offline stays instant.
	git -C "$repo" fetch --quiet --all >/dev/null 2>&1 || true
	base=""
	for ref in origin/main origin/master main master; do
		if git -C "$repo" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then base="$ref"; break; fi
	done
	if [ -n "$base" ] && [ -n "$branch" ]; then
		counts="$(git -C "$repo" rev-list --left-right --count "$base"...HEAD 2>/dev/null || echo '? ?')"
		behind="$(echo "$counts" | awk '{print $1}')"
		ahead="$(echo "$counts" | awk '{print $2}')"
		echo "   vs $base: +$ahead ahead / -$behind behind"
		if [ "${behind:-0}" -gt 0 ]; then
			echo "   ⚠ merge needed: $base is $behind commits ahead of this branch"
			fail=1
		fi
		if [ "${ahead:-0}" -gt 20 ]; then
			echo "   ⚠ $ahead commits on this branch are not on $base yet: merge or land them"
			fail=1
		fi
	fi

	# Bump detection: a dirty addon whose manifest version equals its CHANGELOG
	# top version carries changes without a release bump. Parity itself is
	# enforced by check-addons; this catches "changed but not bumped".
	if [ -d "$repo/system/addons" ]; then
		for manifest in "$repo"/system/addons/*/manifest.md; do
			[ -f "$manifest" ] || continue
			addon="$(basename "$(dirname "$manifest")")"
			if [ -z "$(git -C "$repo" status --porcelain -- "system/addons/$addon")" ]; then continue; fi
			version="$(grep -m1 '^version:' "$manifest" | awk '{print $2}')"
			changelog="$(dirname "$manifest")/CHANGELOG.md"
			[ -f "$changelog" ] || continue
			top="$(grep -E '^## \[' "$changelog" | grep -v Unreleased | head -1 | sed -E 's/^## \[([^]]+)\].*/\1/')"
			if [ "$version" = "$top" ]; then
				# The changelog being dirty in the same tree means the bump was
				# just documented with these changes: that is a pending commit,
				# not a missing bump.
				if [ -z "$(git -C "$repo" status --porcelain -- "$changelog")" ]; then
					echo "   ⚠ bump nodig: $addon has changes but is still version $version (CHANGELOG top: $top)"
					fail=1
				fi
			fi
		done
	fi
	echo ""
done

if [ "$fail" -ne 0 ]; then
	echo "changes: attention needed (see ⚠ above)"
else
	echo "changes: clean"
fi
exit 0  # report-only: the pre-flight never blocks, it makes drift visible
