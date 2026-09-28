#!/usr/bin/env bash
# Find every place a symbol lives, split by what the place IS.
#
# A rename is safe or unsafe depending on the category of the file it lands in:
# code must change, copy must not, and evidence (a record of what something used
# to be called) must not either. Grep alone does not make that distinction, which
# is how a rename ends up rewriting a user-visible sentence.
#
# Usage: sweep.sh <symbol> [root...]
set -euo pipefail

SYMBOL="${1:?usage: sweep.sh <symbol> [root...]}"
shift || true
ROOTS=("$@")
[[ ${#ROOTS[@]} -eq 0 ]] && ROOTS=(.)

# Directories that hold build output or dependencies: a hit there is a copy of a
# hit somewhere else, and renaming it changes nothing.
PRUNE=(-name node_modules -o -name dist -o -name build -o -name .git -o -name vendor -o -name target)

# Paths whose content is read by a person, not executed. A rename must not touch these.
is_copy() {
  case "$1" in
    */i18n/*|*/locales/*|*/messages*|*.po|*.pot|*.strings|*/copy/*) return 0 ;;
  esac
  return 1
}

# Paths that record history: what a thing was called, what a judgement was based on.
is_evidence() {
  case "$1" in
    */docs/*|*/CHANGELOG*|*.md|*/decisions/*|*/handover/*|*bewijs*|*/fixtures/*) return 0 ;;
  esac
  return 1
}

if [[ ${#SYMBOL} -lt 5 ]]; then
  echo "WARNING: '$SYMBOL' is ${#SYMBOL} characters. Too short for an automatic replacement."
  echo "         Short names sit as fragments inside other words and in running text."
  echo "         Go through the hits by hand."
  echo
fi

# Newline-delimited strings, not arrays: an empty bash array expands to one empty
# argument, which made every empty category report a count of 1.
code=""; copy=""; evidence=""
while IFS= read -r f; do
  if is_copy "$f"; then copy+="$f"$'\n'
  elif is_evidence "$f"; then evidence+="$f"$'\n'
  else code+="$f"$'\n'; fi
# -print0/-0: a path with a space in it must not become two paths.
done < <(find "${ROOTS[@]}" \( "${PRUNE[@]}" \) -prune -o -type f -print0 2>/dev/null |
         xargs -0 grep -lw -- "$SYMBOL" 2>/dev/null | sort -u)

show() {
  local heading="$1" list="$2"
  local n=0
  [[ -n "$list" ]] && n=$(printf '%s' "$list" | grep -c '')
  printf '\n== %s (%d) ==\n' "$heading" "$n"
  [[ -z "$list" ]] && return
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    printf '%s  (%dx)\n' "$f" "$(grep -cw -- "$SYMBOL" "$f" || echo 0)"
  done <<< "$list"
}

show "CODE -- rename" "$code"
show "COPY -- do NOT rename, a person reads this" "$copy"
show "EVIDENCE -- do NOT rename, this records what it was called" "$evidence"

printf '\nAfter the rename, verify with the type check and the full test suite.\n'
printf 'Do NOT read the diff: a leak in the copy looks correct in a diff.\n'
