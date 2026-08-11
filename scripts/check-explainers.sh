#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-explainers — norm gate for brain-explain themes + explainers.
# CSS-scan (deny-list, over theme.css): non-OKLCH color, gradient-text,
#   side-stripe accent, cursive on body/p.
# content-scan (over rendered explainer HTML): em-dash / -- in *visible copy*
#   (FAIL) + sentences over 40 words (WARN, copy-norms rule 2). The full
#   writing system (positive rules, not just bans): system/explainers/copy-norms.md.
#   <style>/<script> blocks are stripped first — the ban is about copy, not the
#   CSS comments and color tokens the renderer inlines. Shortcode separators
#   (`- a — b`) live only in the markdown bron and are consumed at render time,
#   so they never reach the HTML; scanning the bron would false-positive on them.
# Env: EXPLAINERS_THEMES (default system/explainers/themes),
#      EXPLAINERS_DIR (default local/explainers).
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT_DIR" || exit 1
THEMES="${EXPLAINERS_THEMES:-system/explainers/themes}"
EXPDIR="${EXPLAINERS_DIR:-local/explainers}"
errors=0

# --- CSS-scan ---
while IFS= read -r css; do
	[ -f "$css" ] || continue
	# strip color-mix(in oklch ...) so its inner refs do not false-positive, then deny non-OKLCH.
	stripped="$(sed -E 's/color-mix\([^)]*\)//g' "$css")"
	if printf '%s' "$stripped" | grep -qiE '#[0-9a-f]{3,8}\b|[^a-z-]rgba?\(|[^a-z-]hsla?\(|[^a-z-]color\('; then
		echo "FAIL $css: non-OKLCH color (use oklch())" >&2; errors=$((errors+1))
	fi
	grep -qiE 'background-clip:[[:space:]]*text' "$css" && { echo "FAIL $css: gradient-text (background-clip:text)" >&2; errors=$((errors+1)); }
	grep -qiE 'border-(left|right):[[:space:]]*[2-9][0-9]*px' "$css" && { echo "FAIL $css: side-stripe border" >&2; errors=$((errors+1)); }
	grep -qiE '(^|[^-])(body|p)\b[^{]*\{[^}]*cursive' "$css" && { echo "FAIL $css: cursive on body/p (script only on headings)" >&2; errors=$((errors+1)); }
done < <(find "$THEMES" -name theme.css 2>/dev/null)

# --- content-scan (rendered html; visible copy only) ---
while IFS= read -r f; do
	[ -f "$f" ] || continue
	# Strip non-prose regions before scanning: style/script blocks and code
	# spans. CLI flags (`--force`) and code legitimately contain `--`; the ban
	# is about visible prose only. Also strip the HTML tags themselves: class-
	# attributen zoals `ex-icon--warn` (BEM-modifier) zijn geen zichtbare copy
	# en gaven false positives op elke explainer met een icoon-callout.
	visible="$(sed -e '/<style/,/<\/style>/d' -e '/<script/,/<\/script>/d' \
		-e '/<pre/,/<\/pre>/d' "$f" | sed -e 's|<code[^>]*>[^<]*</code>||g' \
		-e 's|<[^>]*>||g')"
	printf '%s' "$visible" | grep -qE '—|[^-]--[^-]' && { echo "FAIL $f: em-dash / -- in copy" >&2; errors=$((errors+1)); }
	# copy-norms rule 2 (system/explainers/copy-norms.md): sentences over 40
	# words suggest slop. WARN only — table cells and lists concatenate into
	# pseudo-sentences, so this stays a signal, not a gate.
	long_n="$(printf '%s' "$visible" | awk 'BEGIN{RS="[.!?]"} NF>40{n++} END{print n+0}')"
	[ "${long_n:-0}" -gt 0 ] && echo "WARN $f: $long_n sentence(s) over 40 words (copy-norms rule 2)"
done < <(find "$EXPDIR" -name '*.html' 2>/dev/null)

# --- MOC-membership: every explainer subdir must be linked in the index MOC ---
MOC="$EXPDIR/index.md"
if [ -f "$MOC" ]; then
	while IFS= read -r note; do
		slug="$(basename "$(dirname "$note")")"
		[ "$slug" = "$(basename "$EXPDIR")" ] && continue
		grep -q "\[\[$slug" "$MOC" || { echo "FAIL $note: not linked in the MOC ($MOC)" >&2; errors=$((errors+1)); }
	done < <(find "$EXPDIR" -mindepth 2 -name index.md 2>/dev/null)
fi

if [ "$errors" -eq 0 ]; then echo "check-explainers: ok"; else echo "check-explainers: $errors error(s)" >&2; fi
[ "$errors" -eq 0 ]
