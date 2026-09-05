#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-shim-staging.sh — a commit staged through a symlink must not be empty.
#
# scripts/doctor.sh is a link to scripts/checks/doctor.sh, and so are twenty
# others. `git add scripts/doctor.sh` stages the LINK, whose blob has not
# changed, so git records nothing and says nothing. Three commits went out that
# way with messages describing work that never entered the tree.
#
# The state alone cannot tell that mistake from a deliberate partial commit:
# in both, a link's target is dirty and unstaged. The first version of this
# guard refused on the state and thereby refused every partial commit made
# while any shim target was dirty, which is how its author ended up stashing
# around it five times in one afternoon.
#
# So it is split by what can actually be known:
#   --list      print "link -> target" for every dirty, unstaged shim target
#   --warn      the same, as a warning to stderr; always exits 0   (pre-commit)
#   --message   exit 1 only when the commit MESSAGE names one of those files:
#               then the commit claims work it does not carry     (commit-msg)
set -uo pipefail

MODE=""; MSG=""
for a in "$@"; do
	case "$a" in
	--list) MODE=list ;;
	--warn) MODE=warn ;;
	--message) MODE=message ;;
	-h | --help) sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
	-*) echo "check-shim-staging: unknown option: $a" >&2; exit 2 ;;
	*) MSG="$a" ;;
	esac
done
[ -n "$MODE" ] || { echo "check-shim-staging: need --list, --warn or --message <file>" >&2; exit 2; }

root="$(cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" && pwd -P)"
cd "$root" || exit 0

dirty=() # "link<TAB>target"
while IFS= read -r -d '' entry; do
	mode="${entry%% *}"; link="${entry#*$'\t'}"
	[[ "$mode" = 120000 && -L "$link" ]] || continue
	dest="$(readlink "$link")"
	abs="$(cd "$(dirname "$link")/$(dirname "$dest")" 2>/dev/null && pwd -P)/$(basename "$dest")"
	rel="${abs#"$root"/}"
	[[ -f "$abs" ]] || continue
	git diff --quiet -- "$rel" 2>/dev/null && continue          # target clean
	git diff --cached --quiet -- "$rel" 2>/dev/null || continue # target staged: deliberate
	dirty+=("$link"$'\t'"$rel")
done < <(git ls-files -s -z)

[ "${#dirty[@]}" -gt 0 ] || exit 0

case "$MODE" in
list)
	for d in "${dirty[@]}"; do printf '%s -> %s\n' "${d%%$'\t'*}" "${d#*$'\t'}"; done
	;;
warn)
	echo "pre-commit: note: a symlink's target has changes this commit does not carry:" >&2
	for d in "${dirty[@]}"; do printf '   %s -> %s\n' "${d%%$'\t'*}" "${d#*$'\t'}" >&2; done
	echo "   Fine for a partial commit. If this commit is MEANT to carry it, stage the real path." >&2
	;;
message)
	[ -f "$MSG" ] || exit 0
	claimed=()
	for d in "${dirty[@]}"; do
		link="${d%%$'\t'*}"; rel="${d#*$'\t'}"
		for name in "$link" "$rel" "$(basename "$rel")"; do
			if grep -qF -- "$name" "$MSG"; then claimed+=("$link -> $rel"); break; fi
		done
	done
	[ "${#claimed[@]}" -gt 0 ] || exit 0
	echo "✗ commit-msg: the message names a file this commit does not carry:" >&2
	for c in "${claimed[@]}"; do printf '   %s\n' "$c" >&2; done
	echo "   Staging the link stages the link. Stage the real path (right of the arrow)." >&2
	exit 1
	;;
esac
exit 0
