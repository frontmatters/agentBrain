#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# git-env.sh — drop the repository git handed to a hook.
#
# When a hook runs from a linked worktree, git exports
# GIT_DIR=<main>/.git/worktrees/<name> to it. The hook runs doctor, doctor runs
# tests, and a test that builds a fixture with `git -C "$TMP" init` inherits
# that variable, and GIT_DIR wins over -C and over cwd. So the fixture's
# `git config user.email`, `git init --bare` and `git commit` landed on the
# real checkout: a test identity on 179 commits, core.bare=true, seven fixture
# commits on a release branch. Every push made from a worktree did this.
#
# Usage:  source "$ROOT/scripts/lib/git-env.sh"; clear_git_env
clear_git_env() {
	unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
		GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_CONFIG_PARAMETERS
}
