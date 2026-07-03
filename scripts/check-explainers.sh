#!/usr/bin/env bash
# check-explainers — norm gate for brain-explain themes + explainers.
# CSS-scan (deny-list, over theme.css): non-OKLCH color, gradient-text,
#   side-stripe accent, cursive on body/p.
# content-scan (over rendered explainer HTML): em-dash / -- in *visible copy*.
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
	visible="$(sed -e '/<style/,/<\/style>/d' -e '/<script/,/<\/script>/d' "$f")"
	printf '%s' "$visible" | grep -qE '—|[^-]--[^-]' && { echo "FAIL $f: em-dash / -- in copy" >&2; errors=$((errors+1)); }
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
