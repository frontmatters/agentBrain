#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-enforcement.sh — A learning about a trap must say how it is enforced.
#
# Why this exists. On 2026-09-15 an agent wrote a learning about a bash pitfall and then
# walked into that same pitfall four more times within hours; a second learning about
# backticks inside a css`` template fared no better, three times. The knowledge was in the
# vault and it changed nothing, for three reasons:
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
#   A (hard, zero guesswork) — a learning that CLAIMS `enforcement: hook|gate` must name it
#     in `enforced_by:` and that target must exist. A claim pointing at nothing is worse
#     than no claim: you believe you are covered.
#   B (ratchet) — learnings tagged as a trap with no `enforcement:` field at all. The count
#     may only fall, the same mechanism the English ratchet uses, so the backlog is visible
#     and shrinking instead of blocking work today.
#
# Usage: bash scripts/checks/check-enforcement.sh [--list]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR"

RATCHET="scripts/checks/.enforcement-ratchet.json"
LIST=0
[ "${1:-}" = "--list" ] && LIST=1

# Tags a learning uses to call itself a trap. Taken from what the vault already uses
# rather than invented here — see `grep -h '^tags:' vault/learnings/*.md`.
TRAP_TAGS="gotcha valkuil valkuilen trap traps pitfall bug-class"

veld() { # veld <bestand> <sleutel> — read one frontmatter key
	awk -v k="$2" '
		NR==1 && $0!="---" {exit}
		NR>1 && $0=="---" {exit}
		$0 ~ "^"k":" {sub("^"k": *",""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}
	' "$1"
}

is_trap() { # tags line contains one of TRAP_TAGS
	local tags; tags="$(veld "$1" tags | tr -d '[]' | tr ',' ' ')"
	local t
	for t in $TRAP_TAGS; do
		case " $tags " in *" $t "*) return 0 ;; esac
	done
	return 1
}

errors=0
onbeschermd=0
onbeschermd_lijst=()

while IFS= read -r f; do
	[ -f "$f" ] || continue
	case "$f" in */extracted/*) continue ;; esac  # machine-generated, not curated rules
	case "$(basename "$f")" in README.md | _example.md) continue ;; esac

	mode="$(veld "$f" enforcement)"

	# --- A: a claim must point at something that exists ---
	case "$mode" in
		hook | gate)
			doel="$(veld "$f" enforced_by)"
			if [ -z "$doel" ]; then
				echo "FAIL $f claims enforcement: $mode but names no enforced_by." >&2
				echo "  -> add enforced_by: <path to the hook or gate that catches this>" >&2
				errors=$((errors + 1))
			elif [ ! -e "$doel" ] && ! command -v "${doel%% *}" >/dev/null 2>&1; then
				echo "FAIL $f claims enforcement: $mode via '$doel', which does not exist." >&2
				echo "  -> a claimed guard that is gone is worse than none: you believe you are covered." >&2
				errors=$((errors + 1))
			fi
			;;
		none | '') : ;;
		*)
			echo "FAIL $f has enforcement: '$mode' — expected hook, gate or none." >&2
			errors=$((errors + 1))
			;;
	esac

	# --- B: a trap with no declaration at all ---
	if [ -z "$mode" ] && is_trap "$f"; then
		onbeschermd=$((onbeschermd + 1))
		onbeschermd_lijst+=("$f")
	fi
done < <(find learnings vault/learnings vault/spaces/*/learnings -name '*.md' 2>/dev/null)

if [ "$LIST" = 1 ]; then
	printf '%s\n' "${onbeschermd_lijst[@]:-}" | sed '/^$/d'
fi

plafond="$(sed -n 's/.*"unclassified" *: *\([0-9]*\).*/\1/p' "$RATCHET" 2>/dev/null || true)"
plafond="${plafond:-$onbeschermd}"

if [ "$onbeschermd" -gt "$plafond" ]; then
	echo "FAIL trap learnings without an enforcement declaration: $plafond -> $onbeschermd (may only fall)." >&2
	echo "  -> add 'enforcement: hook|gate|none' to the new one. Run with --list to see which." >&2
	errors=$((errors + 1))
elif [ "$onbeschermd" -lt "$plafond" ]; then
	echo "note: ratchet can drop $plafond -> $onbeschermd; update $RATCHET."
fi

if [ "$errors" -gt 0 ]; then
	echo "check-enforcement: $errors probleem(en)." >&2
	exit 1
fi
echo "check-enforcement: ok ($onbeschermd trap-learnings zonder afdwinging, plafond $plafond)"
