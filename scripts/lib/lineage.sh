#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# lineage.sh: make a checkout follow ONE source, whichever it is.
#
# agentBrain has two lineages that share tag names on different commits: the
# private one (Gitea, LAN bundles, candidates) and the public one (GitHub, a
# rewriting snapshot per release). A checkout that switches between the LAN
# installer and the online installer carries tags from both, and a plain
# `git fetch --tags` refuses a same-named tag in silence ("would clobber
# existing tag"): `git describe` then yields a bare hash and the checkout
# cannot say which release it is. Measured on an updated consumer machine:
# 28 tags, v1.10.4 on the Gitea commit, describe gave 8042b0c.
#
# adopt_lineage makes the SOURCE win: its tags overwrite same-named ones, tags
# it does not know are pruned, HEAD is reset to its branch, and the result is
# verified: describe must anchor on a v-tag. Sourced by the installer (both
# paths) and by brain-update.sh, so every way in agrees.
#
#   adopt_lineage <checkout> <source> <branch>   source: URL, path or bundle
#   lineage_identity <checkout>                  prints vX.Y.Z[-N-ghash], or nothing
#   sourced: returns 0 when identity anchors, 1 when it is a bare hash

lineage_identity() {
	git -C "$1" describe --tags --match 'v*' 2>/dev/null || true
}

adopt_lineage() {
	local dir="$1" src="$2" branch="$3"
	# +refs/tags/*:refs/tags/* forces same-named tags; --prune-tags drops the
	# ones the source does not carry, so nothing from the other lineage lingers.
	git -C "$dir" fetch -q --force --prune --prune-tags --tags "$src" "$branch" || return 2
	git -C "$dir" reset -q --hard FETCH_HEAD || return 2
	[ -n "$(lineage_identity "$dir")" ]
}
