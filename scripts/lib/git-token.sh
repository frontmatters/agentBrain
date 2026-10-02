# shellcheck shell=bash
# SPDX-License-Identifier: Apache-2.0
# git-token.sh — run git with an Authorization header that is no argument.
#
# `git -c http.extraHeader="Authorization: token $T"` puts the token in git's
# argument list, where process inspection can expose it. git reads the same
# setting from GIT_CONFIG_COUNT / GIT_CONFIG_KEY_n /
# GIT_CONFIG_VALUE_n, which only this process and its children see.
#
#   git_with_token "$TOKEN" -C "$dir" push origin main
#
# An empty token runs plain git. scripts/checks/check-token-argv.sh refuses
# the -c form in the tree.
git_with_token() {
	local token="$1"; shift
	if [ -z "$token" ]; then git "$@"; return; fi
	GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader \
		GIT_CONFIG_VALUE_0="Authorization: token $token" git "$@"
}

# remote_needs_token <repo-dir> <remote>: true when the remote is http(s), the
# only kind that authenticates with a token. An ssh remote uses the machine's
# key: no token is fetched at all, so there is nothing to leak or to go stale
# when a token is rotated (the root fix: prefer ssh remotes).
remote_needs_token() {
	case "$(git -C "$1" remote get-url --push "$2" 2>/dev/null)" in
		http://*|https://*) return 0 ;;
		*) return 1 ;;
	esac
}
