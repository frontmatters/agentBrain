#!/usr/bin/env bash
# scanman-validate.sh — agent-agnostic completeness check for a scanman workspace.
#
# Exit codes:
#   0  PASS — workspace appears complete-enough (03/04/05 materially filled)
#   1  FAIL — workspace is incomplete; agent must iterate
#   2  ERROR — usage / workspace path problem

set -uo pipefail

usage() {
  cat >&2 <<EOF
Usage: scanman-validate.sh <workspace-dir>

Checks if a scanman canonical workspace is "complete enough":
  - all required files exist (00, 00b, 01, 02, 03, 04, 05, index)
  - 03/04/05 contain no template placeholders
  - 03/04/05 meet minimum word count (default: 300)
  - 03/04/05 contain minimum substantial bullets (default: 3, >=30 chars)

Returns non-zero with explicit per-file feedback if incomplete.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

WS="$1"
if [[ ! -d "$WS" ]]; then
  echo "ERROR: workspace not found: $WS" >&2
  exit 2
fi

MIN_WORDS="${SCANMAN_MIN_WORDS:-300}"
MIN_ITEMS="${SCANMAN_MIN_ITEMS:-3}"
MIN_BULLET_LEN="${SCANMAN_MIN_BULLET_LEN:-30}"
MIN_CLAIM_LABELS="${SCANMAN_MIN_CLAIM_LABELS:-3}"
MIN_SECTION_WORDS="${SCANMAN_MIN_SECTION_WORDS:-25}"
MAX_THIN_SECTIONS="${SCANMAN_MAX_THIN_SECTIONS:-2}"
EXEMPT_SECTIONS_REGEX="${SCANMAN_EXEMPT_SECTIONS:-^(Related|Purpose|Decision)$}"
PLACEHOLDER_REGEX='\[fill in\]|\bTODO\b|\bTBD\b|\bFIXME\b|\bXXX\b'
CLAIM_LABEL_REGEX='\b(verified|inferred|unknown)\b'

REQUIRED_FILES=(
  "index.md"
  "00-file-inventory.md"
  "00b-dependency-map.md"
  "01-system-map.md"
  "02-runtime-model.md"
  "03-core-primitives.md"
  "04-risk-and-bloat.md"
  "05-redesign-v1.md"
)

# Files that must pass the "materially filled" deep checks (not just existence)
DEEP_CHECK_FILES=(
  "03-core-primitives.md"
  "04-risk-and-bloat.md"
  "05-redesign-v1.md"
)

# Files that must demonstrate epistemic discipline via claim-labels.
# Includes 02 because strict-runtime requires verified-only main pseudocode (SKILL.md).
DISCIPLINE_FILES=(
  "02-runtime-model.md"
  "03-core-primitives.md"
  "04-risk-and-bloat.md"
  "05-redesign-v1.md"
)

FAIL=0
declare -a FAIL_REASONS=()

fail() {
  FAIL=1
  FAIL_REASONS+=("$1")
}

check_exists() {
  local file="$1"
  if [[ ! -f "$WS/$file" ]]; then
    fail "$file: MISSING"
    return 1
  fi
  return 0
}

check_no_placeholders() {
  local file="$1"
  local matches
  matches=$(grep -oE "$PLACEHOLDER_REGEX" "$WS/$file" 2>/dev/null | sort -u | paste -sd ',' -)
  if [[ -n "$matches" ]]; then
    fail "$file: contains placeholders [$matches]"
  fi
}

check_word_count() {
  local file="$1"
  local words
  words=$(wc -w < "$WS/$file" | tr -d ' ')
  if [[ "$words" -lt "$MIN_WORDS" ]]; then
    fail "$file: $words words < $MIN_WORDS minimum"
  fi
}

check_substantial_items() {
  local file="$1"
  local items
  items=$(grep -cE "^[[:space:]]*[-*][[:space:]].{${MIN_BULLET_LEN},}" "$WS/$file" 2>/dev/null)
  [[ -z "$items" ]] && items=0
  if [[ "$items" -lt "$MIN_ITEMS" ]]; then
    fail "$file: $items substantial bullets (>= ${MIN_BULLET_LEN} chars) < $MIN_ITEMS minimum"
  fi
}

check_claim_labels() {
  local file="$1"
  local count
  count=$(grep -ciE "$CLAIM_LABEL_REGEX" "$WS/$file" 2>/dev/null)
  [[ -z "$count" ]] && count=0
  if [[ "$count" -lt "$MIN_CLAIM_LABELS" ]]; then
    fail "$file: $count claim-labels (verified/inferred/unknown) < $MIN_CLAIM_LABELS minimum"
  fi
}

# Evidence-link check (opt-in, default off). Closes the v0.0.4 gap where an agent
# could pass the gate with correct-by-luck `verified` claims that were never
# grounded in actual source reads. When enabled, every file with `verified`
# claims must contain at least one source-path reference (e.g. `src/foo.ts`).
# v0.0.6 may add a stricter mode requiring file:line references.
# Only code extensions count as source-path evidence. `.md`, `.json`, `.yaml`,
# `.toml` are excluded because cross-references to workspace docs (e.g.
# `00-file-inventory.md`) would otherwise pass for free.
EVIDENCE_PATH_REGEX='[a-zA-Z0-9_.@/-]+\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|zig|rs|go|py|sh|c|cpp|h|hpp|java|rb|php|swift|kt|scala)\b'

check_evidence_links() {
  local file="$1"
  local verified_count evidence_count
  verified_count=$(grep -cE '\bverified\b' "$WS/$file" 2>/dev/null)
  [[ -z "$verified_count" ]] && verified_count=0
  if [[ "$verified_count" -eq 0 ]]; then
    return
  fi
  evidence_count=$(grep -cE "$EVIDENCE_PATH_REGEX" "$WS/$file" 2>/dev/null)
  [[ -z "$evidence_count" ]] && evidence_count=0
  if [[ "$evidence_count" -eq 0 ]]; then
    fail "$file: $verified_count verified claim(s) but zero source-path references — claims must be grounded in actual file reads"
  fi
}

check_thin_sections() {
  # Detects sections (## ...) whose body is below MIN_SECTION_WORDS.
  # Catches the "fill only one table, leave everything else as template boilerplate" shortcut.
  # MAX_THIN_SECTIONS=1 tolerates one legitimately short section (e.g. Open Questions).
  local file="$1"
  local thin_report
  thin_report=$(awk -v min="$MIN_SECTION_WORDS" -v exempt="$EXEMPT_SECTIONS_REGEX" '
    function emit() {
      if (cur != "" && !match(cur, exempt) && count < min) {
        printf "%s|%d\n", cur, count;
      }
    }
    /^## / { emit(); cur = $0; sub(/^## +/, "", cur); count = 0; next }
    /^---$/ { in_fm = !in_fm; next }
    in_fm { next }
    { for (i = 1; i <= NF; i++) count++ }
    END { emit() }
  ' "$WS/$file" 2>/dev/null)

  if [[ -z "$thin_report" ]]; then
    return
  fi

  local thin_count
  thin_count=$(printf '%s\n' "$thin_report" | grep -c .)
  if [[ "$thin_count" -le "$MAX_THIN_SECTIONS" ]]; then
    return
  fi

  while IFS='|' read -r section words; do
    [[ -z "$section" ]] && continue
    fail "$file: thin section '## $section' ($words words < $MIN_SECTION_WORDS) — template boilerplate likely unfilled"
  done <<< "$thin_report"
}

# Existence pass (all required files)
for f in "${REQUIRED_FILES[@]}"; do
  check_exists "$f" || true
done

# Deep checks (only on the files that must be materially filled)
for f in "${DEEP_CHECK_FILES[@]}"; do
  if [[ -f "$WS/$f" ]]; then
    check_no_placeholders "$f"
    check_word_count "$f"
    check_substantial_items "$f"
  fi
done

# Epistemic discipline checks (02/03/04/05 must use claim-labels)
for f in "${DISCIPLINE_FILES[@]}"; do
  if [[ -f "$WS/$f" ]]; then
    check_claim_labels "$f"
  fi
done

# Section-density checks (03/04/05 — catches single-table-only enrichment)
for f in "${DEEP_CHECK_FILES[@]}"; do
  if [[ -f "$WS/$f" ]]; then
    check_thin_sections "$f"
  fi
done

# Evidence-link check (opt-in via SCANMAN_REQUIRE_EVIDENCE=1).
# Applied to 02/03/04 only — 05 (redesign) refers to primitives from 03 by
# name, not to source files, so requiring source-paths there would be wrong.
EVIDENCE_CHECK_FILES=(
  "02-runtime-model.md"
  "03-core-primitives.md"
  "04-risk-and-bloat.md"
)
if [[ "${SCANMAN_REQUIRE_EVIDENCE:-0}" == "1" ]]; then
  for f in "${EVIDENCE_CHECK_FILES[@]}"; do
    if [[ -f "$WS/$f" ]]; then
      check_evidence_links "$f"
    fi
  done
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "PASS: $WS is complete-enough"
  echo "  - all required files exist"
  echo "  - 03/04/05 contain no placeholders"
  echo "  - 03/04/05 meet word count (>= $MIN_WORDS)"
  echo "  - 03/04/05 meet substantial items (>= $MIN_ITEMS bullets, >= $MIN_BULLET_LEN chars)"
  echo "  - 02/03/04/05 demonstrate claim discipline (>= $MIN_CLAIM_LABELS verified/inferred/unknown labels)"
  echo "  - 03/04/05 have <= $MAX_THIN_SECTIONS thin sections (>= $MIN_SECTION_WORDS words per section, except $EXEMPT_SECTIONS_REGEX)"
  exit 0
else
  echo "FAIL: $WS is incomplete" >&2
  for reason in "${FAIL_REASONS[@]}"; do
    echo "  - $reason" >&2
  done
  echo "" >&2
  echo "Agent must iterate to fill missing/insufficient content before claiming completion." >&2
  exit 1
fi
