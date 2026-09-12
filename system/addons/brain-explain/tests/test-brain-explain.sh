#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"; cd "$ROOT_DIR" || exit 1
BE="bash system/addons/brain-explain/bin/brain-explain"
passed=0; failed=0; failures=()
assert(){ if [ "$2" = "$3" ]; then passed=$((passed+1)); else failed=$((failed+1)); failures+=("$1: got '$2' want '$3'"); fi; }

assert "help exits 0"      "$($BE --help >/dev/null 2>&1; echo $?)" "0"
assert "help names render" "$($BE --help 2>&1 | grep -c 'brain-explain render')" "1"
assert "unknown subcmd fails" "$($BE bogus >/dev/null 2>&1; echo $?)" "1"

# --- Task 2: markdown + shortcode parser ---
TMP=$(mktemp -d)
cat > "$TMP/n.md" <<'EOF'
---
type: explainer
theme: clean-flat
---
# Title
Intro paragraph with `code` and a [[wikilink]].

:::layers
- **a** — first
- **b** — second
:::

:::callout
A pull quote.
:::

:::bogus
fallback content
:::
EOF
out="$($BE render "$TMP/n.md" --out "$TMP/n.html" >/dev/null 2>&1; cat "$TMP/n.html" 2>/dev/null)"
assert "renders h1"        "$(echo "$out" | grep -Ec '<h1[^>]*>Title</h1>')" "1"
assert "layers class"      "$(echo "$out" | grep -c 'class="layers"')" "1"
assert "layer items"       "$(echo "$out" | grep -o 'class="layer"' | wc -l | tr -d ' ')" "2"
assert "callout class"     "$(echo "$out" | grep -c 'class="pull"')" "1"
assert "unknown->blockquote" "$(echo "$out" | grep -c '<blockquote>')" "1"
assert "inline code"       "$(echo "$out" | grep -c '<code>code</code>')" "1"
rm -rf "$TMP"

# --- Task 3: renderer assembly (theme precedence, inline norm+theme CSS) ---
TMP=$(mktemp -d); cat > "$TMP/n.md" <<'EOF'
---
type: explainer
theme: clean-flat
---
# Hi
Body.
EOF
$BE render "$TMP/n.md" --out "$TMP/n.html" >/dev/null 2>&1
assert "html has data-theme" "$(grep -c '<html lang="nl" data-theme="clean-flat"' "$TMP/n.html")" "1"
assert "override wins"        "$($BE render "$TMP/n.md" --theme editorial --out "$TMP/e.html" >/dev/null 2>&1; grep -c '<html lang="nl" data-theme="editorial"' "$TMP/e.html")" "1"
assert "norm css inlined"     "$(grep -c '/\* brain-explain norm \*/' "$TMP/n.html")" "1"
assert "no external css link"  "$(grep -c '<link rel=.stylesheet' "$TMP/n.html")" "0"
rm -rf "$TMP"

# --- Task 4: norm skeleton + 3 reference themes + categories ---
for t in clean-flat whiteboard editorial; do
  css="system/explainers/themes/$t/theme.css"
  assert "$t defines --ink"  "$(grep -c -- '--ink:' "$css" 2>/dev/null)" "1"
  assert "$t defines body"   "$(grep -c 'body{' "$css" 2>/dev/null)" "1"
  assert "$t styles h2"      "$(grep -c 'h2' "$css" 2>/dev/null)" "1"
done
assert "categories has addons" "$(grep -c '^addons$' system/explainers/categories.txt 2>/dev/null)" "1"

# --- Task 5: check-explainers norm gate (CSS-scan + content-scan) ---
TMP=$(mktemp -d)
mkdir -p "$TMP/good/g" "$TMP/bad/b" "$TMP/empty"
printf 'body{color:oklch(0.3 0.01 70)}\nh2{font-weight:600}\n' > "$TMP/good/g/theme.css"
printf 'body{color:#112233}\nh2{}\n' > "$TMP/bad/b/theme.css"
assert "good theme passes" "$(EXPLAINERS_THEMES="$TMP/good" EXPLAINERS_DIR="$TMP/empty" bash scripts/checks/check-explainers.sh >/dev/null 2>&1; echo $?)" "0"
err="$(EXPLAINERS_THEMES="$TMP/bad" EXPLAINERS_DIR="$TMP/empty" bash scripts/checks/check-explainers.sh 2>&1 || true)"
assert "hex flagged"        "$(echo "$err" | grep -c 'non-OKLCH color')" "1"
# content-scan: em-dash in rendered copy (visible text, not CSS/script)
mkdir -p "$TMP/exp/x"; printf '<p>een — dash</p>' > "$TMP/exp/x/x.html"
err2="$(EXPLAINERS_DIR="$TMP/exp" EXPLAINERS_THEMES="$TMP/good" bash scripts/checks/check-explainers.sh 2>&1 || true)"
assert "em-dash flagged"    "$(echo "$err2" | grep -c 'em-dash')" "1"
# content-scan must ignore em-dash inside <style> (CSS comments / tokens)
mkdir -p "$TMP/exp2/y"; printf '<style>\n/* a — b */\nbody{color:oklch(0.3 0.01 70)}\n</style>\n<p>clean copy</p>\n' > "$TMP/exp2/y/y.html"
ok2="$(EXPLAINERS_DIR="$TMP/exp2" EXPLAINERS_THEMES="$TMP/good" bash scripts/checks/check-explainers.sh >/dev/null 2>&1; echo $?)"
assert "style em-dash ignored" "$ok2" "0"
rm -rf "$TMP"

# --- Task 6: theme_creator (generate -> validate -> repair -> fail-exit) ---
TMP=$(mktemp -d)
ok="$(BRAIN_EXPLAIN_LLM=mockok EXPLAINERS_LOCAL_THEMES="$TMP/themes" $BE theme new mine --prompt "warm" >/dev/null 2>&1; echo $?)"
assert "compliant theme written, exit 0" "$ok" "0"
assert "theme.css exists" "$([ -f "$TMP/themes/mine/theme.css" ] && echo 1 || echo 0)" "1"
bad="$(BRAIN_EXPLAIN_LLM=mockbad EXPLAINERS_LOCAL_THEMES="$TMP/themes" $BE theme new bad --prompt "x" >/dev/null 2>&1; echo $?)"
assert "non-compliant after 3 passes, non-zero exit" "$bad" "1"
assert "no half-written bad theme" "$([ -f "$TMP/themes/bad/theme.css" ] && echo 1 || echo 0)" "0"
rm -rf "$TMP"

# --- Task 7: onboard.sh first-run theme setup (LLM check, clean-flat fallback) ---
TMP=$(mktemp -d)
# No LLM reachable + non-interactive => idempotent, exits 0, suggests clean-flat fallback.
out="$(BRAIN_EXPLAIN_NO_LLM=1 EXPLAINERS_CONFIG="$TMP/config.json" EXPLAINERS_LOCAL_THEMES="$TMP/themes" bash system/addons/brain-explain/onboard.sh </dev/null 2>&1; echo "rc=$?")"
assert "onboard no-llm exits 0" "$(echo "$out" | grep -c 'rc=0')" "1"
assert "onboard suggests clean-flat" "$(echo "$out" | grep -ic 'themes/clean-flat')" "1"
rm -rf "$TMP"

# --- Task 8: MOC + membership check ---
assert "MOC lists brain-explain" "$(grep -Ec '^- \[\[brain-explain\]\]' vault/explainers/index.md 2>/dev/null)" "1"
# membership: an explainer dir not linked in the MOC fails the check
TMP=$(mktemp -d); mkdir -p "$TMP/orphan"; printf -- '---\ntype: explainer\n---\n# Orphan\n' > "$TMP/orphan/index.md"
printf '# MOC\n' > "$TMP/index.md"
err="$(EXPLAINERS_DIR="$TMP" EXPLAINERS_THEMES="system/explainers/themes" bash scripts/checks/check-explainers.sh 2>&1 || true)"
assert "orphan flagged" "$(echo "$err" | grep -c 'not linked in the MOC')" "1"
rm -rf "$TMP"

echo "passed=$passed failed=$failed"; for f in "${failures[@]:-}"; do [ -n "$f" ] && echo "FAIL: $f"; done
[ "$failed" -eq 0 ]
