#!/usr/bin/env bash
# Fail on configured foreign-language words in scoped, non-localized product files.
set -euo pipefail
FACTORY='' LANE=next
while [ "$#" -gt 0 ]; do
  case "$1" in
    --factory) FACTORY=${2:?missing factory path}; shift 2 ;;
    --lane) LANE=${2:?missing lane}; shift 2 ;;
    *) echo "factory-language-check: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$FACTORY" ] || { echo 'usage: factory-language-check.sh --factory PATH [--lane dev|next]' >&2; exit 2; }
case "$LANE" in dev|next) ;; *) echo "factory-language-check: invalid lane: $LANE" >&2; exit 2 ;; esac
FACTORY="$(cd "$FACTORY" && pwd -P)"
CONFIG="$FACTORY/factory.json"
[ -f "$CONFIG" ] || { echo "factory-language-check: missing $CONFIG" >&2; exit 2; }
# Do not impose jq on factories that did not opt in, but never mistake a
# malformed factory.json for an unconfigured factory.
state="$(python3 - "$CONFIG" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    assert isinstance(data, dict)
except (OSError, ValueError, AssertionError):
    print('INVALID')
else:
    print('ENABLED' if data.get('languageCheck') is not None else 'DISABLED')
PY
)"
case "$state" in
  DISABLED) echo 'factory-language-check: SKIP (no languageCheck configured)'; exit 0 ;;
  ENABLED) ;;
  *) echo 'factory-language-check: invalid factory.json' >&2; exit 2 ;;
esac
command -v jq >/dev/null || { echo 'factory-language-check: jq is required' >&2; exit 2; }
LANGUAGE="$(jq -r '.languageCheck.language // empty' "$CONFIG")"
LANE_PATH="$(jq -r --arg lane "$LANE" '.lanes[$lane] // empty' "$CONFIG")"
[ -n "$LANGUAGE" ] && [ -n "$LANE_PATH" ] || { echo 'factory-language-check: missing language or lane' >&2; exit 2; }
case "$LANE_PATH" in \~/*) LANE_PATH="$HOME/${LANE_PATH#\~/}" ;; esac
ROOT="$(cd "$LANE_PATH" && pwd -P)" || exit 2
LIST="$(jq -r '.languageCheck.wordList // empty' "$CONFIG")"
if [ -n "$LIST" ]; then
  case "$LIST" in /*|*../*|*/..|..|*\\*) echo 'factory-language-check: unsafe wordList path' >&2; exit 2 ;; esac
  LIST="$FACTORY/$LIST"
  [ -f "$LIST" ] || { echo 'factory-language-check: wordList file missing' >&2; exit 2; }
  LIST="$(realpath "$LIST")"
  case "$LIST" in "$FACTORY"/*) ;; *) echo 'factory-language-check: wordList escapes factory' >&2; exit 2 ;; esac
else
  LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/languages.json"
fi
jq -e --arg lang "$LANGUAGE" '.[$lang].forbidden | type == "object" and length > 0' "$LIST" >/dev/null || {
  echo "factory-language-check: no word lists for $LANGUAGE" >&2; exit 2;
}
PATHS="$(jq -r '.languageCheck.paths | if type == "array" then .[] else empty end' "$CONFIG")"
[ -n "$PATHS" ] || { echo 'factory-language-check: paths must be a nonempty array' >&2; exit 2; }
errors=0; files=0
while IFS= read -r relative; do
  case "$relative" in ''|/*|*../*|*/..|..|*\\*) echo "factory-language-check: unsafe path: $relative" >&2; exit 2 ;; esac
  file="$ROOT/$relative"
  [ -f "$file" ] || { echo "factory-language-check: missing file: $relative" >&2; exit 2; }
  resolved="$(realpath "$file")"
  case "$resolved" in "$ROOT"/*) ;; *) echo "factory-language-check: path escapes lane: $relative" >&2; exit 2 ;; esac
  files=$((files+1))
  # The lists contain literal words; -w bounds alphabetic scripts to whole words.
  # CJK words occur inside unspaced text, so search those as substrings.
  while IFS=$'\t' read -r source word; do
    [ -n "$word" ] || { echo "factory-language-check: empty word for $source" >&2; exit 2; }
    [ "$source" != "$LANGUAGE" ] || { echo 'factory-language-check: target language in forbidden list' >&2; exit 2; }
    # An empty array under set -u crashes macOS Bash 3.2. Keep options scalar.
    case "$source" in zh|ja|ko) grep_flags=-niF ;; *) grep_flags=-niFw ;; esac
    while IFS=: read -r line _; do
      [ -n "$line" ] || continue
      text="$(awk -v n="$line" 'NR == n { print; exit }' "$file")"
      case "$text" in *[![:space:]]*) ;; *) continue ;; esac
      # Comments are not user-facing copy. Only full-line comments are exempt.
      if printf '%s\n' "$text" | grep -Eq '^[[:space:]]*(#|//|\*)'; then continue; fi
      printf '%s:%s: forbidden %s word %s for %s\n' "$relative" "$line" "$source" "$word" "$LANGUAGE"
      errors=$((errors+1))
    done < <(grep "$grep_flags" -- "$word" "$file" 2>/dev/null || true)
  done < <(jq -r --arg lang "$LANGUAGE" '.[$lang].forbidden | to_entries[] | .key as $source | .value[] | [$source, .] | @tsv' "$LIST")
done <<< "$PATHS"
if [ "$errors" -gt 0 ]; then echo "factory-language-check: FAIL ($errors finding(s), $files file(s))"; exit 1; fi
echo "factory-language-check: PASS (0 finding(s), $files file(s))"
