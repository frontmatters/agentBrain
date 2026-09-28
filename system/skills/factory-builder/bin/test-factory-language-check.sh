#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/next"
printf '{"lanes":{"next":"%s/next"},"languageCheck":{"language":"en","paths":["cli.txt"]}}\n' "$TMP" > "$TMP/factory.json"
CHECK=(bash "$HERE/factory-language-check.sh" --factory "$TMP")
printf 'Examples: add a channel\n' > "$TMP/next/cli.txt"
"${CHECK[@]}" | grep -q 'PASS'
for text in Voorbeelden Beispiele Exemples Exemplos Ejemplos Esempi Przykłady Örnekler Примеры '使用方法：请选择' '使い方はこちら' '사용법 안내' أمثلة उदाहरण; do
  printf '%s\n' "$text" > "$TMP/next/cli.txt"
  if "${CHECK[@]}" > "$TMP/output"; then echo "FAIL: missed $text" >&2; exit 1; fi
  grep -q 'FAIL' "$TMP/output"
done
# The CJK path must also work with the macOS system Bash (3.2 + set -u).
printf '使用方法：请选择\n' > "$TMP/next/cli.txt"
if /bin/bash "$HERE/factory-language-check.sh" --factory "$TMP" > "$TMP/output" 2>&1; then
  echo 'FAIL: macOS Bash missed CJK copy' >&2; exit 1
fi
grep -q 'forbidden zh word' "$TMP/output"
if grep -q 'unbound variable' "$TMP/output"; then echo 'FAIL: macOS Bash crashed on an empty array' >&2; exit 1; fi
printf '{"fr":{"forbidden":{"en":["Examples"]}}}\n' > "$TMP/words.json"
jq '.languageCheck += {"language":"fr","wordList":"words.json"}' "$TMP/factory.json" > "$TMP/new.json"
mv "$TMP/new.json" "$TMP/factory.json"
printf 'Examples\n' > "$TMP/next/cli.txt"
if "${CHECK[@]}" > "$TMP/output"; then echo 'FAIL: custom list missed English' >&2; exit 1; fi
printf 'Exemples\n' > "$TMP/next/cli.txt"
"${CHECK[@]}" | grep -q 'PASS'
rm "$TMP/next/cli.txt"
if "${CHECK[@]}" > "$TMP/output" 2>&1; then echo 'FAIL: missing file passed' >&2; exit 1; fi
jq 'del(.languageCheck)' "$TMP/factory.json" > "$TMP/new.json"
mv "$TMP/new.json" "$TMP/factory.json"
"${CHECK[@]}" | grep -q 'SKIP'
printf '{malformed json\n' > "$TMP/factory.json"
if "${CHECK[@]}" > "$TMP/output" 2>&1; then echo 'FAIL: malformed config passed as unconfigured' >&2; exit 1; fi
grep -q 'invalid factory.json' "$TMP/output"
echo 'factory language check: PASS'
