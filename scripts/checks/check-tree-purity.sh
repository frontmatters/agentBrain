#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-tree-purity.sh — the public tree holds the framework and its addons, nothing else.
#
# What ships is `git ls-files`: safe against untracked clutter, blind to tracked
# working notes placed in a public directory. Thirty implementation plans shipped
# in every archive since v1.10.0 that way, and a personal spike, and vault-shaped
# directories (learnings/, projects/, sessions/) that made the checkout look like
# a vault and invited real notes in. Every guard checked content: names,
# secrets, characters. None checked shape.
#
# The rule: a top-level entry is either framework (system/, scripts/, templates/,
# docs/, hooks, agent config) or root metadata. Seeds for the vault live under
# templates/vault/. Everything else belongs in the vault.
#
# Two things are held to the list: the tracked tree, and the `!/name` allowlist
# in .gitignore (fail-closed root). A `!/name` line for something not on the
# list is the door being propped open.
set -uo pipefail
ROOT="$(cd -P "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd -P)"
cd "$ROOT" || exit 1
ALLOWED="system scripts templates docs .githooks .github .claude \
README.md LICENSE NOTICE SECURITY.md VERSION CHANGELOG.md CLAUDE.md setup.sh .gitignore .cursorrules .windsurfrules"
allowed() { local x; for x in $ALLOWED; do [ "$1" = "$x" ] && return 0; done; return 1; }
fail=0
while IFS= read -r top; do
	allowed "$top" || { echo "  tracked outside the framework: $top" >&2; fail=1; }
done < <(git ls-files | awk -F/ '{print $1}' | sort -u)
while IFS= read -r line; do
	name="${line#!/}"; name="${name%/}"
	allowed "$name" || { echo "  .gitignore re-admits a non-framework root entry: $line" >&2; fail=1; }
done < <(grep -E '^!/' .gitignore)
if [ "$fail" -ne 0 ]; then
	echo "check-tree-purity: FAILED. The public tree is framework + addons; working notes and vault-shaped" >&2
	echo "  directories belong in the vault, seeds under templates/vault/. Allowed roots: $ALLOWED" >&2
	exit 1
fi
echo "check-tree-purity: ok ($(git ls-files | awk -F/ '{print $1}' | sort -u | wc -l | tr -d ' ') root entries, all framework)"
