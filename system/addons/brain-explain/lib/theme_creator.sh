#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# theme_creator — LLM generates a theme.css; the check-explainers norm-scan is the
# oracle. generate -> validate -> repair (max 3 passes). Only a norm-compliant
# theme is written; after 3 failed passes nothing is written (no half-built theme).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
LOCAL_THEMES="${EXPLAINERS_LOCAL_THEMES:-$ROOT/vault/explainers/themes}"

[ "${1:-}" = "new" ] || { echo "usage: brain-explain theme new <name> --prompt \"...\"" >&2; exit 2; }
name="${2:?theme name required}"; shift 2
prompt=""; [ "${1:-}" = "--prompt" ] && prompt="${2:-}"

NORM_CONTRACT='OKLCH only (no hex/rgb/hsl), readable body font, script only on headings, no background-clip:text, no border-left/right>1px accents, no em-dash in copy. Define tokens --bg --ink --soft --accent and style body,.kicker,h1,h2,h3,.lead,.layers .layer,.cards .card,.pull,.note,code,footer.'

# Call an LLM backend; emit raw CSS on stdout. Mock backends for tests.
gen() { # $1 = feedback (violations) or empty
	case "${BRAIN_EXPLAIN_LLM:-ollama:gpt-oss:20b-cloud}" in
		mockok)  printf 'body{color:oklch(0.3 0.01 70)}\n.kicker{}\nh1{}\nh2{font-weight:600}\nh3{}\n.lead{}\n.layers .layer{}\n.cards .card{}\n.pull{}\n.note{}\ncode{}\nfooter{}\n' ;;
		mockbad) printf 'body{color:#123456}\nh2{}\n' ;;
		ollama:*|ollama-cloud:*) ollama run "${BRAIN_EXPLAIN_LLM#*:}" <<EOF
Write a CSS theme for an explainer page. Constraints: $NORM_CONTRACT
Style description: $prompt
${1:+Fix these violations from the previous attempt: $1}
Output ONLY css, no fences, no prose.
EOF
		;;
		*) echo "theme_creator: unknown backend '$BRAIN_EXPLAIN_LLM'" >&2; return 1 ;;
	esac
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/cand/$name" "$tmp/empty"
feedback=""
for pass in 1 2 3; do
	gen "$feedback" | sed -E 's/^```.*$//' > "$tmp/cand/$name/theme.css"
	if violations="$(EXPLAINERS_THEMES="$tmp/cand" EXPLAINERS_DIR="$tmp/empty" bash "$ROOT/scripts/checks/check-explainers.sh" 2>&1)"; then
		mkdir -p "$LOCAL_THEMES/$name"
		cp "$tmp/cand/$name/theme.css" "$LOCAL_THEMES/$name/theme.css"
		echo "✓ theme '$name' written to $LOCAL_THEMES/$name/theme.css"
		exit 0
	fi
	feedback="$violations"; echo "  pass $pass: norm violations, retrying…" >&2
done
echo "✗ theme '$name' did not pass the norms after 3 passes. Nothing written." >&2
echo "  Remaining violations:" >&2; echo "$feedback" >&2
echo "  Fallback: cp -r '$ROOT/system/explainers/themes/clean-flat' '$LOCAL_THEMES/$name' and edit." >&2
exit 1
