#!/usr/bin/env bash
# Fetch the word lists the language verdict reads, into a cache that is not committed.
#
# Which lists exist is `wordlists.tsv` next to this script; adding a language is one line
# there. A list dropped into the cache by hand is used too, as long as it is `<code>.txt`:
# the verdict reads the cache, not the manifest.
#
#   bash system/lib/language/fetch-wordlists.sh            # everything in the manifest
#   bash system/lib/language/fetch-wordlists.sh nl en      # only these
#   bash system/lib/language/fetch-wordlists.sh --force    # re-fetch what is already there
#
# They are fetched rather than vendored because together they run to tens of megabytes,
# which does not belong in a framework repo.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="${AGENTBRAIN_WORDLIST_CACHE:-$HOME/.cache/agentbrain/wordlists}"
MANIFEST="$HERE/wordlists.tsv"
mkdir -p "$CACHE"

FORCE=0
REQUESTED=()
for a in "$@"; do
  if [ "$a" = "--force" ]; then FORCE=1; else REQUESTED+=("$a"); fi
done

wanted() {
  [ ${#REQUESTED[@]} -eq 0 ] && return 0
  local c; for c in "${REQUESTED[@]}"; do [ "$c" = "$1" ] && return 0; done
  return 1
}

fetched=0
while IFS=$'\t' read -r code src format license name; do
  case "$code" in ''|\#*) continue ;; esac
  wanted "$code" || continue
  target="$CACHE/${code}.txt"

  if [ -s "$target" ] && [ "$FORCE" -eq 0 ]; then
    printf '  %-4s %-12s %s words (already present)\n' "$code" "$name" "$(wc -l < "$target" | tr -d ' ')"
    fetched=$((fetched + 1)); continue
  fi

  if [ "$src" = "SYSTEM" ]; then
    if [ -s /usr/share/dict/words ]; then
      cp -f /usr/share/dict/words "$target"
    else
      echo "  $code: no /usr/share/dict/words on this machine; skipped" >&2; continue
    fi
  else
    curl -fsSL --max-time 180 -o "$target.tmp" "$src" \
      || { echo "  $code: fetch failed ($src)" >&2; rm -f "$target.tmp"; continue; }
    # A truncated download is worse than none: it silently shrinks the vocabulary, and a
    # verdict built on half a dictionary calls real words foreign.
    n=$(wc -l < "$target.tmp" | tr -d ' ')
    if [ "$n" -lt 10000 ]; then
      echo "  $code: arrived too small ($n lines); not kept" >&2; rm -f "$target.tmp"; continue
    fi
    # A frequency list is "word count"; keep the word. Doing this after the size check
    # means a truncated download is still caught on its raw line count.
    if [ "$format" = "freq" ]; then
      awk '{print $1}' "$target.tmp" > "$target.tmp2" && mv "$target.tmp2" "$target.tmp"
    fi
    mv "$target.tmp" "$target"
  fi
  printf '  %-4s %-12s %s words  [%s]\n' "$code" "$name" "$(wc -l < "$target" | tr -d ' ')" "$license"
  fetched=$((fetched + 1))
done < "$MANIFEST"

echo "cache: $CACHE  ($fetched list(s))"
