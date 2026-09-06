#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-vault-hygiene.sh — foreign material does not belong in the vault.
#
# The vault holds knowledge, and everything in it is held to that standard:
# frontmatter, a path-derived id, resolving wiki-links, a filename that feeds
# the search index. A cloned repository cannot meet that standard and should
# not be asked to.
#
# This happened, and the numbers are the argument. An 89 MB third-party clone
# placed inside a space produced 2521 schema failures. Teaching the validator to
# skip it looked like the fix and made things worse: with those files out of the
# index, 19 dead wiki-links became 4926, because thousands of foreign basenames
# (README, index, SKILL) had been silently resolving real notes' broken links.
# The material was the problem, not the check.
#
# So this warns and names where the material belongs, rather than pruning it and
# leaving it to rot in the wrong place. It never fails the build: a clone that is
# mid-review is a normal state, and a check that blocks work teaches people to
# skip checks.
#
# A space is not foreign: it is a nested repository on purpose, and its notes are
# exactly what the validator exists to validate. The passport is what tells them
# apart, so the rule is derived rather than declared.
#
# Usage: check-vault-hygiene.sh [--quiet]
set -uo pipefail

BRAIN="${BRAIN_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
VAULT="$BRAIN/vault"
QUIET=0
for a in "$@"; do
	case "$a" in
		--quiet) QUIET=1 ;;
		-h|--help) sed -n '3,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "check-vault-hygiene: unknown option: $a" >&2; exit 2 ;;
	esac
done
[ -d "$VAULT" ] || { echo "check-vault-hygiene: no vault — skip"; exit 0; }

WORKSPACE="$(cd -P "$(readlink "$VAULT" 2>/dev/null || echo "$VAULT")/.." 2>/dev/null && pwd -P)/workspace"

found=0
# A nested repository that carries no space passport is somebody else's code.
while IFS= read -r gitdir; do
	d="$(dirname "$gitdir")"
	rel="${d#"$VAULT"/}"
	grep -qm1 '^type: space' "$d/index.md" 2>/dev/null && continue
	n="$(find "$d" -type f -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
	sz="$(du -sh "$d" 2>/dev/null | cut -f1 | tr -d ' ')"
	if [ "$QUIET" -eq 0 ]; then
		echo "  ⚠ vault/$rel — a checkout with no space passport ($n files, $sz)" >&2
	fi
	found=$((found + 1))
done < <(find -L "$VAULT" -name .git -maxdepth 6 2>/dev/null | grep -v "^$VAULT/.git$")

if [ "$found" -eq 0 ]; then
	echo "check-vault-hygiene: ok (no foreign checkouts in the vault)"
	exit 0
fi

cat >&2 <<EOF
check-vault-hygiene: $found foreign checkout(s) inside the vault.

Everything in the vault is validated as knowledge. A third-party checkout
cannot pass that and should not have to. Move it beside the vault instead:

    mv <path> ${WORKSPACE}/external/

What you learn from it belongs in the vault as a note that stands on its own.
The raw material does not. See ${WORKSPACE}/README.md.
EOF
exit 0   # a warning, never a gate: a clone mid-review is a normal state
