#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# retrofit-work-notes.sh — list or fix the work-note WARN backlog (MUST gaps).
#
# MECHANISM ONLY. What a work note MUST carry lives in system/work-note-contract.tsv;
# the scope lives in system/ratchets.tsv. This script reads both (agentBrain principle
# 1, system/principles.md); it never hardcodes the contract.
#
# Retrofit is opportunistic: run it to see the debt, or apply per note when you touch
# one. It is never a forced mass rewrite.
#
# Usage:
#   retrofit-work-notes.sh                 # list work notes missing MUST fields
#   retrofit-work-notes.sh --apply <file>  # insert missing MUST stubs into <file>
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CONTRACT="$ROOT_DIR/system/work-note-contract.tsv"
REGISTRY="$ROOT_DIR/system/ratchets.tsv"
[ -f "$CONTRACT" ] && [ -f "$REGISTRY" ] || { echo "retrofit: missing config" >&2; exit 1; }

# Load MUST fields from the contract (key, location, label, regex).
M_KEYS=(); M_LOCS=(); M_LABELS=(); M_REGEXES=()
while IFS=$'\t' read -r key tier loc label regex; do
	case "$key" in '' | \#*) continue ;; esac
	[ "$tier" = "MUST" ] || continue
	M_KEYS+=("$key"); M_LOCS+=("$loc"); M_LABELS+=("$label"); M_REGEXES+=("$regex")
done < "$CONTRACT"

# --- apply mode -------------------------------------------------------------
if [ "${1:-}" = "--apply" ]; then
	f="${2:-}"
	[ -f "$f" ] || { echo "retrofit --apply <file>: file not found: $f" >&2; exit 2; }
	# Locale-aware headings (i18n): insert in the note's own locale, values from the
	# catalog, fallback to the contract label. Never hardcoded here.
	rf_locale="en"
	if [ -f "$ROOT_DIR/scripts/lib/locale.sh" ]; then
		# shellcheck source=scripts/lib/locale.sh disable=SC1091
		. "$ROOT_DIR/scripts/lib/locale.sh"
		rf_locale="$(locale_for "$f" "$ROOT_DIR")"
	fi
	rf_cat="$ROOT_DIR/system/i18n/${rf_locale}/work-note.tsv"
	[ -f "$rf_cat" ] || rf_cat="$ROOT_DIR/system/i18n/en/work-note.tsv"
	added=""
	body_insert=""
	i=0
	while [ "$i" -lt "${#M_KEYS[@]}" ]; do
		if ! grep -qiE "${M_REGEXES[$i]}" "$f"; then
			if [ "${M_LOCS[$i]}" = "frontmatter" ]; then
				# Insert the field into the frontmatter (after the first '---').
				awk -v field="${M_LABELS[$i]}" '
					NR==1 && $0=="---" { print; print field " TODO"; ins=1; next } { print }
				' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
			else
				hd=""; gd=""
				if [ -f "$rf_cat" ]; then
					hd="$(awk -F'\t' -v key="${M_KEYS[$i]}" '!/^#/ && $1==key{print $2; exit}' "$rf_cat")"
					gd="$(awk -F'\t' -v key="${M_KEYS[$i]}" '!/^#/ && $1==key{print $3; exit}' "$rf_cat")"
				fi
				[ -n "$hd" ] || hd="${M_LABELS[$i]}"
				[ -n "$gd" ] || gd="see system/work-note-contract.md"
				body_insert="${body_insert}${hd}\n\n<!-- ${gd} -->\n\n"
			fi
			added="${added} ${M_KEYS[$i]}"
		fi
		i=$((i + 1))
	done
	# Insert body sections right after the first H1 heading.
	if [ -n "$body_insert" ]; then
		awk -v ins="$body_insert" '
			!done && /^# / { print; print ""; printf "%s", ins; done=1; next } { print }
		' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
	fi
	if [ -n "$added" ]; then echo "retrofit: added ->$added  in $f"; else echo "retrofit: $f already complete"; fi
	exit 0
fi

# --- list mode --------------------------------------------------------------
scope="$(awk -F'\t' '!/^#/ && $1=="work-note-contract"{print $3; exit}' "$REGISTRY")"
LOCAL_DIR="$(cd local 2>/dev/null && pwd -P)" || { echo "retrofit: no vault/ layer"; exit 0; }
WORKNOTES="$(grep -rIl --include='*.md' -E "^type: (${scope})\$" "$LOCAL_DIR" 2>/dev/null \
	| grep -viE '/(extracted|quarantine|graphify-out|\.trash|\.git|templates|legacy)/|youtube-digest' || true)"

total=0
while IFS= read -r f; do
	[ -f "$f" ] || continue
	missing=""
	i=0
	while [ "$i" -lt "${#M_KEYS[@]}" ]; do
		grep -qiE "${M_REGEXES[$i]}" "$f" || missing="${missing} ${M_KEYS[$i]}"
		i=$((i + 1))
	done
	if [ -n "$missing" ]; then
		echo "$f  missing:$missing"
		total=$((total + 1))
	fi
done <<< "$WORKNOTES"
echo "retrofit: $total work note(s) miss one or more MUST fields — fix with: retrofit-work-notes.sh --apply <file>"
