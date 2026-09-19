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
HIER="$(cd "$(dirname "$0")" && pwd)"
CACHE="${AGENTBRAIN_WORDLIST_CACHE:-$HOME/.cache/agentbrain/wordlists}"
MANIFEST="$HIER/wordlists.tsv"
mkdir -p "$CACHE"

FORCE=0
GEVRAAGD=()
for a in "$@"; do
  if [ "$a" = "--force" ]; then FORCE=1; else GEVRAAGD+=("$a"); fi
done

wil() {
  [ ${#GEVRAAGD[@]} -eq 0 ] && return 0
  local c; for c in "${GEVRAAGD[@]}"; do [ "$c" = "$1" ] && return 0; done
  return 1
}

gehaald=0
while IFS=$'\t' read -r code bron vorm licentie naam; do
  case "$code" in ''|\#*) continue ;; esac
  wil "$code" || continue
  doel="$CACHE/${code}.txt"

  if [ -s "$doel" ] && [ "$FORCE" -eq 0 ]; then
    printf '  %-4s %-12s %s woorden (al aanwezig)\n' "$code" "$naam" "$(wc -l < "$doel" | tr -d ' ')"
    gehaald=$((gehaald + 1)); continue
  fi

  if [ "$bron" = "SYSTEM" ]; then
    if [ -s /usr/share/dict/words ]; then
      cp -f /usr/share/dict/words "$doel"
    else
      echo "  $code: geen /usr/share/dict/words op deze machine; overgeslagen" >&2; continue
    fi
  else
    curl -fsSL --max-time 180 -o "$doel.tmp" "$bron" \
      || { echo "  $code: ophalen mislukt ($bron)" >&2; rm -f "$doel.tmp"; continue; }
    # A truncated download is worse than none: it silently shrinks the vocabulary, and a
    # verdict built on half a dictionary calls real words foreign.
    n=$(wc -l < "$doel.tmp" | tr -d ' ')
    if [ "$n" -lt 10000 ]; then
      echo "  $code: kwam te klein binnen ($n regels); niet bewaard" >&2; rm -f "$doel.tmp"; continue
    fi
    # A frequency list is "word count"; keep the word. Doing this after the size check
    # means a truncated download is still caught on its raw line count.
    if [ "$vorm" = "freq" ]; then
      awk '{print $1}' "$doel.tmp" > "$doel.tmp2" && mv "$doel.tmp2" "$doel.tmp"
    fi
    mv "$doel.tmp" "$doel"
  fi
  printf '  %-4s %-12s %s woorden  [%s]\n' "$code" "$naam" "$(wc -l < "$doel" | tr -d ' ')" "$licentie"
  gehaald=$((gehaald + 1))
done < "$MANIFEST"

echo "cache: $CACHE  ($gehaald lijst(en))"
