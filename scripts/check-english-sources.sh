#!/usr/bin/env bash
# check-english-sources.sh — Verify that locale-sensitive strings live in locale.ts only,
# and that source code comments across system/addons are in English.
#
# Rule: Dutch user-visible strings (section headers, TODO placeholders, LLM prompt language)
# must be centralized in locale.ts, not scattered across source files.
# Rule: Source code comments (not template content) must be in English.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FAIL=0

# ---------------------------------------------------------------------------
# 1. Locale-sensitive strings must not appear outside locale.ts
# ---------------------------------------------------------------------------
# These strings are Dutch user-visible content; they must only live in locale.ts.
LOCALE_STRINGS=(
  "## Samenvatting"
  "Claude kan dit invullen"
  "Wordt ingevuld door Claude"
  "SAMENVATTING:"
)

for needle in "${LOCALE_STRINGS[@]}"; do
  # Search TypeScript source files; exclude locale.ts (canonical home) and test files
  hits="$(grep -rn \
    --include="*.ts" \
    --exclude="*.test.ts" \
    --exclude-dir=node_modules \
    -F "$needle" \
    system/addons/ 2>/dev/null \
    | grep -v "/locale\." \
    | grep -v "/locale.ts" \
    || true)"
  if [ -n "$hits" ]; then
    printf 'check-english-sources: Dutch locale string "%s" found outside locale.ts:\n' "$needle"
    printf '%s\n' "$hits" | head -5 | sed 's/^/  /'
    FAIL=1
  fi
done

# ---------------------------------------------------------------------------
# 2. Dutch in source code comments (TypeScript, shell — not template content)
# ---------------------------------------------------------------------------
# Detect comment lines with Dutch-only words. We match `//` and `*` comment lines
# that contain unambiguously Dutch words to avoid false positives.
# "zijn" / "wordt" / "kunnen" / "niet" / "naar" are rare in English comments.
DUTCH_COMMENT_PATTERNS=(
  "^[[:space:]]*//.*(wordt|kunnen|zijn|naar|voor zover|bij voorkeur|verplicht)"
  "^[[:space:]]*\*[[:space:]]*(wordt|kunnen|zijn|naar|voor zover|bij voorkeur|verplicht)"
)

for pat in "${DUTCH_COMMENT_PATTERNS[@]}"; do
  hits="$(grep -rn \
    --include="*.ts" \
    --include="*.sh" \
    --exclude-dir=node_modules \
    -iE "$pat" \
    system/addons/ scripts/ 2>/dev/null \
    | grep -v "/locale\." \
    | grep -v "/locale.ts" \
    | grep -v "scripts/check-" \
    || true)"
  if [ -n "$hits" ]; then
    printf 'check-english-sources: Dutch comment detected (use English for source code):\n'
    printf '%s\n' "$hits" | head -5 | sed 's/^/  /'
    FAIL=1
  fi
done

# ---------------------------------------------------------------------------
# 3. Dutch in markdown documentation under system/ (the public layer)
# ---------------------------------------------------------------------------
# Policy: everything outside local/ must be in English. The locale/comment checks
# above only cover .ts/.sh under system/addons + scripts; markdown docs (SKILL.md,
# READMEs, templates, playbooks) anywhere in system/ are not covered. Flag any
# Dutch-dominant system/ markdown via the canonical detector (shared with the
# promote skill's gate, so the two cannot drift). Fixtures are exempt — they may
# simulate a Dutch local vault as test data.
DETECT="$ROOT_DIR/scripts/lib/dutch-dominant.sh"

while IFS= read -r f; do
  if bash "$DETECT" "$f"; then
    printf 'check-english-sources: Dutch markdown in system/ (must be English): %s\n' "${f#./}"
    FAIL=1
  fi
done < <(find system -name "*.md" -not -path "*/node_modules/*" -not -path "*/fixtures/*" 2>/dev/null)

if [ "$FAIL" -eq 1 ]; then
  printf 'check-english-sources: FAIL\n' >&2
  exit 1
fi

printf 'check-english-sources: OK\n'
