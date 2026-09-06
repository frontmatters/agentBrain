#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# report-stale.sh — notes gone cold: never accessed, or last touched past a
# type-aware threshold. On-demand report (NOT doctor-wired), always exits 0 —
# staleness is an opportunity to review/archive, not a failure (cf. report-orphans.sh).
#
# The "last touched" date is the LATER of the access-index `last` (local/.access-index.json)
# and the note's frontmatter `date`. Weight never hides a search hit; this report is the
# only place usage drives an action, and even here it only *suggests*.
#
# Usage:
#   bash scripts/reports/report-stale.sh            # count + per-folder breakdown
#   bash scripts/reports/report-stale.sh --list     # also print each stale note
#   bash scripts/reports/report-stale.sh --json     # structured output
set -euo pipefail

# AGENTBRAIN_TEST_ROOT lets the test point the report at a fixture vault.
BASE="${AGENTBRAIN_TEST_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$BASE"
[ -d vault ] || { echo "report-stale: no vault/ — nothing to report (PASS)"; exit 0; }

MODE="${1:-}"
IDX="vault/.access-index.json"
TODAY_TS="$(date +%s)"

# type → stale-after-days
threshold() {
  case "$1" in
    session) echo 30 ;;
    project|backlog) echo 180 ;;
    learning|troubleshoot|reference|preference) echo 365 ;;
    *) echo 180 ;;
  esac
}

# Skip only truly archival/machine areas. NOTE: sessions ARE in scope here (unlike
# report-orphans) — a stale session is exactly the fast-decay note worth archiving.
SKIP_RE='^vault/(archive|legacy|extracted|graphify-out|quarantine|\.trash|tmp|logs|backups|spaces)/'

# Preload the access index: rel-path -> last-date.
declare -A LAST
if [ -f "$IDX" ]; then
  while IFS=$'\t' read -r p l; do LAST["$p"]="$l"; done \
    < <(jq -r 'to_entries[] | "\(.key)\t\(.value.last)"' "$IDX" 2>/dev/null || true)
fi

# Portable YYYY-MM-DD -> epoch (BSD date first, GNU date fallback).
to_ts() { date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || echo ""; }

fm() { # first frontmatter value for key $2 in file $1
  awk -F': *' -v k="$2" 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n==1 && $1==k {gsub(/["\r]/,"",$2); print $2; exit}' "$1"
}

count=0
declare -A PERFOLDER
JSON="[]"

while IFS= read -r f; do
  rel="${f#./}"
  ident="local/${rel#vault/}"   # notes are reported by their identity, the spelling every id and index key uses
  [[ "$rel" =~ $SKIP_RE ]] && continue
  typ="$(fm "$f" type)"
  fdate="$(fm "$f" date)"
  last="${LAST[local/${rel#vault/}]:-}"   # the index keys on the local/ identity
  # reference date = the LATER of access-last and frontmatter-date
  ref="$last"
  if [ -z "$ref" ] || { [ -n "$fdate" ] && [[ "$fdate" > "$ref" ]]; }; then ref="$fdate"; fi
  [ -z "$ref" ] && continue
  ref_ts="$(to_ts "$ref")"; [ -z "$ref_ts" ] && continue
  age=$(( (TODAY_TS - ref_ts) / 86400 ))
  thr="$(threshold "${typ:-}")"
  [ "$age" -le "$thr" ] && continue
  count=$((count+1))
  folder="${rel%/*}"
  PERFOLDER["$folder"]=$(( ${PERFOLDER["$folder"]:-0} + 1 ))
  [ "$MODE" = "--list" ] && printf '  %-55s %-12s %4dd (stale >%sd)\n' "$ident" "${typ:-?}" "$age" "$thr"
  JSON="$(jq -c --arg p "$ident" --arg t "${typ:-}" --argjson a "$age" --argjson th "$thr" \
    '. += [{path:$p, type:$t, age_days:$a, threshold_days:$th}]' <<<"$JSON")"
done < <(find vault -type f -name '*.md')

if [ "$MODE" = "--json" ]; then
  echo "$JSON"
  exit 0
fi

echo "report-stale: ${count} stale note(s)"
for folder in "${!PERFOLDER[@]}"; do
  printf '  %-45s %d\n' "$folder" "${PERFOLDER[$folder]}"
done | sort
exit 0
