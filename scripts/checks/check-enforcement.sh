#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-enforcement.sh — A learning about a trap must say how it is enforced.
#
# Why this exists. An agent can write a learning about a pitfall and then walk into that
# same pitfall again within hours. The knowledge is in the vault and it changes nothing,
# for three reasons:
#
#   1. Retrieval needs a trigger. These mistakes do not feel like anything at the moment
#      they happen — a wrong working directory reads as "that file does not exist" — so the
#      moment that would prompt a search never arrives.
#   2. The failure is at typing time, not thinking time. The wrong path is the path of
#      least resistance; a document cannot intervene there.
#   3. Recall is probabilistic. Over hundreds of actions, "usually remembered" becomes
#      "regularly forgotten".
#
# What DOES work is already in this repo: check-english.mjs and the note-id hook catch their
# mistakes without anybody remembering anything. The difference is not the quality of the
# prose — it is that they run. So a learning about a trap has to declare whether something
# runs for it.
#
# Two parts, deliberately split by how certain they can be:
#
#   A (hard, zero guesswork) — a learning that CLAIMS `enforcement: hook|gate` must name
#     a guard in `enforced_by:`, that guard must exist, AND the coverage map must link
#     that guard back to the learning. A claim pointing at nothing is worse than no claim:
#     you believe you are covered. Existence alone does not prove that:
#     `enforced_by: README.md` passes an existence test and guards nothing.
#
#     The coverage map is $VAULT_DIR/config/enforcement-covers.tsv, one
#     `<guard-path><TAB><learning-slug>` per line (# starts a comment), the guard
#     spelled exactly as `enforced_by:` spells it. It lives in
#     the vault because the learnings do: shipped code does not name a vault's notes.
#     Without the file the back-link is "not measured" and reported as such; the
#     existence part of A and all of B still run.
#   The vocabulary distinguishes debt from a settled end state:
#     hook | gate  — guarded, and `enforced_by:` names the guard (rule A checks it exists)
#     unenforced   — a guard IS possible, nobody wrote it yet. This is debt and it counts.
#     none         — not mechanically catchable at all. A deliberate end state.
#   If `none` meant both "cannot be caught" and "nobody got to it", the count could
#   reach zero without a single trap being covered: a trap recorded without a guard
#   lets the same bug class return in another file.
#
#   B (ratchet) — learnings tagged as a trap with no `enforcement:` field, plus every
#     learning declared `unenforced`, whatever its tags. The count
#     may only fall, the same mechanism the English ratchet uses, so the backlog is visible
#     and shrinking instead of blocking work today.
#
# Usage: bash scripts/checks/check-enforcement.sh [--list]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR"

# The ratchet compares a count of vault content against a number in git. With
# no vault the find walks an empty tree, the count is 0, and the check reports
# ok: green because it saw nothing, for example in a fresh worktree with no
# vault linked.
# shellcheck source=scripts/lib/vault.sh
. "$ROOT_DIR/scripts/lib/vault.sh"
vault_required check-enforcement || exit $?

RATCHET="scripts/checks/.enforcement-ratchet.json"
COVERS="$VAULT_DIR/config/enforcement-covers.tsv"
LIST=0
[ "${1:-}" = "--list" ] && LIST=1

# Tags a learning uses to call itself a trap. Taken from what the vault already uses
# rather than invented here — see `grep -h '^tags:' vault/learnings/*.md`.
TRAP_TAGS="gotcha valkuil valkuilen trap traps pitfall bug-class"

field() { # field <file> <key>: read one frontmatter key
	awk -v k="$2" '
		NR==1 && $0!="---" {exit}
		NR>1 && $0=="---" {exit}
		$0 ~ "^"k":" {sub("^"k": *",""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}
	' "$1"
}

is_trap() { # tags line contains one of TRAP_TAGS
	local tags; tags="$(field "$1" tags | tr -d '[]' | tr ',' ' ')"
	local t
	for t in $TRAP_TAGS; do
		case " $tags " in *" $t "*) return 0 ;; esac
	done
	return 1
}

covers() { # covers <guard-path> <slug>: does the coverage map link them?
	awk -F'\t' -v g="$1" -v s="$2" '
		/^[ \t]*#/ {next}
		{sub(/\r$/, "")}
		$1 == g && $2 == s {found = 1; exit}
		END {exit found ? 0 : 1}
	' "$COVERS"
}

errors=0
unguarded=0
unguarded_list=()
backlinks_unmeasured=0

while IFS= read -r f; do
	[ -f "$f" ] || continue
	case "$f" in */extracted/*) continue ;; esac  # machine-generated, not curated rules
	case "$(basename "$f")" in README.md | _example.md) continue ;; esac

	mode="$(field "$f" enforcement)"

	# --- A: a claim must point at something that exists ---
	case "$mode" in
		hook | gate)
			target="$(field "$f" enforced_by)"
			if [ -z "$target" ]; then
				echo "FAIL $f claims enforcement: $mode but names no enforced_by." >&2
				echo "  -> add enforced_by: <path to the hook or gate that catches this>" >&2
				errors=$((errors + 1))
			elif [ ! -e "$target" ] && ! command -v "${target%% *}" >/dev/null 2>&1; then
				echo "FAIL $f claims enforcement: $mode via '$target', which does not exist." >&2
				echo "  -> a claimed guard that is gone is worse than none: you believe you are covered." >&2
				errors=$((errors + 1))
			elif [ -f "$target" ] && [ ! -f "$COVERS" ]; then
				backlinks_unmeasured=$((backlinks_unmeasured + 1))
			elif [ -f "$target" ] && ! covers "$target" "$(basename "$f" .md)"; then
				# The claim has to point both ways. Existing is not the same as covering:
				# `enforced_by: README.md` passes an existence test and guards nothing.
				echo "FAIL $f claims enforcement: $mode via '$target', which the coverage map does not link back." >&2
				printf '  -> add "%s\t%s" to %s, or point enforced_by elsewhere.\n' "$target" "$(basename "$f" .md)" "$COVERS" >&2
				errors=$((errors + 1))
			fi
			;;
		none | unenforced | '') : ;;
		*)
			echo "FAIL $f has enforcement: '$mode' — expected hook, gate, unenforced or none." >&2
			errors=$((errors + 1))
			;;
	esac

	# --- B: undeclared traps, plus anything declared as owed ---
	# `unenforced` counts wherever it appears: it is an explicit statement that a
	# guard is possible and missing, so it is debt with or without a trap tag.
	# An empty field only counts on a trap, as before.
	if [ "$mode" = unenforced ] || { [ -z "$mode" ] && is_trap "$f"; }; then
		unguarded=$((unguarded + 1))
		unguarded_list+=("$f")
	fi
done < <(find learnings "$VAULT_DIR/learnings" "$VAULT_DIR"/spaces/*/learnings -name '*.md' 2>/dev/null)

if [ "$LIST" = 1 ]; then
	printf '%s\n' "${unguarded_list[@]:-}" | sed '/^$/d'
fi

ceiling="$(sed -n 's/.*"unclassified" *: *\([0-9]*\).*/\1/p' "$RATCHET" 2>/dev/null || true)"
ceiling="${ceiling:-$unguarded}"

if [ "$unguarded" -gt "$ceiling" ]; then
	echo "FAIL trap learnings without an enforcement declaration: $ceiling -> $unguarded (may only fall)." >&2
	echo "  -> add 'enforcement: hook|gate|unenforced|none' to the new one. Run with --list to see which." >&2
	echo "  -> an honest new 'unenforced' may raise the ceiling; relabelling it 'none' to stay under may not." >&2
	errors=$((errors + 1))
elif [ "$unguarded" -lt "$ceiling" ]; then
	echo "note: ratchet can drop $ceiling -> $unguarded; update $RATCHET."
fi

if [ "$errors" -gt 0 ]; then
	echo "check-enforcement: $errors problem(s)." >&2
	exit 1
fi
if [ "$backlinks_unmeasured" -gt 0 ]; then
	echo "note: guard back-links not measured for $backlinks_unmeasured claim(s): no $COVERS."
fi
echo "check-enforcement: ok ($unguarded trap learnings without enforcement, ceiling $ceiling)"
