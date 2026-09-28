#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# repo-snapshot.sh — notice when a check touches the checkout it runs in.
#
# A test that builds a git fixture does so with `git -C "$TMP"` or `cd "$TMP"`.
# Let $TMP be empty, for any reason, and both of those quietly address the
# current repository instead: `git -C ""` is the cwd, and nothing else
# reports the damage.
#
# So doctor snapshots the repository before each check and compares after:
#   HEAD          a check must not commit here
#   index         a check must not stage here
#   local config  a check must not configure here
#
# The three are not equally attributable. HEAD and the index belong to this
# worktree alone, so a change there happened inside the check. `git config
# --local` does NOT: in a worktree it reads $GIT_COMMON_DIR/config, shared with
# the main checkout and every sibling worktree, and a second session writing
# there moves this snapshot mid-run, even during a check that runs no git
# command at all. That is the third outcome below.
#
# Usage:  source "$ROOT/scripts/lib/repo-snapshot.sh"
#         before="$(repo_snapshot)"; ...run check...; repo_snapshot_diff "$before"
#         0 nothing moved · 1 the check did it · 2 shared state moved, not the check
repo_snapshot() {
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf 'not-a-repo\n'; return 0; }
	printf 'HEAD %s\n' "$(git rev-parse HEAD 2>/dev/null)"
	printf 'BRANCH %s\n' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
	git diff --cached --name-only 2>/dev/null | sed 's/^/INDEX /'
	git config --local --list 2>/dev/null | sort | sed 's/^/CONFIG /'
}

repo_snapshot_diff() { # <before-snapshot>
	local before="$1" after delta
	[ "$before" = "not-a-repo" ] && return 0
	after="$(repo_snapshot)"
	[ "$before" = "$after" ] && return 0
	delta="$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -E '^[<>]')"

	# branch.<name>.merge and branch.<name>.remote are the keys normal
	# concurrent work rewrites: every `push -u`, every checkout of a remote
	# branch. When the whole delta is those and nothing else, no check did
	# this, a neighbour did. Report it rather than swallow it, but do not
	# fail a check that cannot have caused it.
	#
	# Deliberately narrow. A fixture escaping into this repo writes user.*,
	# core.*, remote.* or moves HEAD and the index, and all of those still
	# come out as outcome 1. The gap this leaves is a fixture whose ONLY
	# effect is a branch upstream, which would have to set it without ever
	# creating the branch or moving HEAD.
	if ! printf '%s\n' "$delta" | grep -qvE '^[<>] CONFIG branch\.'; then
		echo "shared state moved while this check ran; the checkout config is shared with every worktree:" >&2
		printf '%s\n' "$delta" | sed 's/^</   was:/; s/^>/   now:/' >&2
		return 2
	fi

	echo "the check touched the checkout it runs in:" >&2
	printf '%s\n' "$delta" | sed 's/^</   was:/; s/^>/   now:/' >&2
	return 1
}
