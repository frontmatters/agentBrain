#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# repo-snapshot.sh — notice when a check touches the checkout it runs in.
#
# A test that builds a git fixture does so with `git -C "$TMP"` or `cd "$TMP"`.
# Let $TMP be empty, for any reason, and both of those quietly address the
# current repository instead: `git -C ""` is the cwd. Measured on this
# machine: the checkout's local config carried a test identity for 179
# commits, core.bare=true appeared one afternoon, and seven fixture commits
# landed on a release branch. Every doctor run in between was green.
#
# So doctor snapshots the repository before each check and compares after:
#   HEAD          a check must not commit here
#   index         a check must not stage here
#   local config  a check must not configure here
#
# Usage:  source "$ROOT/scripts/lib/repo-snapshot.sh"
#         before="$(repo_snapshot)"; ...run check...; repo_snapshot_diff "$before"
#         (prints what changed, exit 1; silent exit 0 when nothing did)
repo_snapshot() {
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf 'not-a-repo\n'; return 0; }
	printf 'HEAD %s\n' "$(git rev-parse HEAD 2>/dev/null)"
	printf 'BRANCH %s\n' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
	git diff --cached --name-only 2>/dev/null | sed 's/^/INDEX /'
	git config --local --list 2>/dev/null | sort | sed 's/^/CONFIG /'
}

repo_snapshot_diff() { # <before-snapshot>
	local before="$1" after
	[ "$before" = "not-a-repo" ] && return 0
	after="$(repo_snapshot)"
	[ "$before" = "$after" ] && return 0
	echo "the check touched the checkout it runs in:" >&2
	diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -E '^[<>]' | sed 's/^</   was:/; s/^>/   now:/' >&2
	return 1
}
