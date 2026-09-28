#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# drop-local-alias.sh: retire the local/ alias of the vault in one checkout.
#
# The vault's link in a checkout is vault/. local/ was the older name and was
# kept as an alias (local -> vault) while the code migrated. Removing it is
# safe only once nothing on the machine resolves through it, and symlinks the
# agents' setup created do: skill links under ~/.claude, ~/.pi and ~/.copilot,
# the memory redirects under ~/.claude/projects/*/memory, Pi extension links.
# So this does two things, in that order, and is idempotent:
#   1. every symlink in those places whose target runs through <brain>/local/
#      is re-pointed to the same path under <brain>/vault/ (same file: the two
#      names are one directory);
#   2. the checkout's local/ is removed when it is our alias (a symlink to
#      vault/). A real directory named local/ is never touched.
#
# The inverse is one command: ln -sfn vault <checkout>/local. Setup no longer
# creates the alias; an older install runs this once.
#
# Usage: drop-local-alias.sh [--dry-run] [--brain <alias-path>] [--checkout <dir>] [<extra-dir>...]
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
DRY=0; BRAIN="${BRAIN_ALIAS:-$HOME/agentBrain}"; CHECKOUT="$ROOT"; EXTRA=()
while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY=1 ;;
		--brain) BRAIN="$2"; shift ;;
		--checkout) CHECKOUT="$2"; shift ;;
		-h|--help) sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) EXTRA+=("$1") ;;
	esac
	shift
done

# Where agent setups put links into the brain. Depth 2 covers <dir>/<name>
# and ~/.claude/projects/<slug>/memory.
PLACES=("$HOME/.claude/skills" "$HOME/.claude/projects" "$HOME/.pi/agent" "$HOME/.copilot/skills" "$HOME/.gemini" "$HOME/.codex" "${EXTRA[@]+"${EXTRA[@]}"}")

repointed=0; kept=0
for place in "${PLACES[@]}"; do
	[ -d "$place" ] || continue
	while IFS= read -r link; do
		target="$(readlink "$link")"
		case "$target" in
			"$BRAIN/local/"*|"$BRAIN/local") ;;
			*) continue ;;
		esac
		new="$BRAIN/vault${target#"$BRAIN/local"}"
		if [ ! -e "$new" ]; then
			echo "  keep   $link -> $target (no such path under vault/; left alone)"
			kept=$((kept + 1)); continue
		fi
		if [ "$DRY" -eq 1 ]; then echo "  would  $link -> $new"
		else ln -sfn "$new" "$link" && echo "  moved  $link -> $new"; fi
		repointed=$((repointed + 1))
	done < <(find "$place" -maxdepth 2 -type l 2>/dev/null)
done

alias_link="$CHECKOUT/local"
if [ -L "$alias_link" ] && [ "$(readlink "$alias_link")" = "vault" ]; then
	if [ "$DRY" -eq 1 ]; then echo "  would  remove $alias_link (alias of vault/)"
	else rm "$alias_link" && echo "  removed $alias_link (alias of vault/)"; fi
elif [ -L "$alias_link" ]; then
	echo "  keep   $alias_link -> $(readlink "$alias_link") (not our alias; left alone)"
elif [ -d "$alias_link" ]; then
	echo "  keep   $alias_link is a real directory; run setup-vault.sh first"
else
	echo "  ok     no local/ alias in $CHECKOUT"
fi
echo "drop-local-alias: $repointed link(s) re-pointed, $kept left alone$([ "$DRY" -eq 1 ] && echo ' (dry run)')"
