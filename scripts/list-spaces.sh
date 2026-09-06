#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# list-spaces.sh — what compartments exist, and what state are they in.
#
# A space slug is deliberately opaque: it is the identifier that travels into
# commits, reports and shared notes, so it must not carry the owner's name. The
# name lives in exactly one place — the passport at local/spaces/<slug>/index.md
# — and this listing is the route to it.
#
# By default the owner is NOT printed. Terminal output ends up in transcripts,
# screenshots and pasted snippets, which is the reach the slug exists to avoid.
# Pass --owner when you actually need the answer.
#
# Usage: list-spaces.sh [--owner] [--json]
set -uo pipefail

BRAIN="${BRAIN_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
SPACES="$BRAIN/vault/spaces"
SHOW_OWNER=0; AS_JSON=0
for a in "$@"; do
  case "$a" in
    --owner) SHOW_OWNER=1 ;;
    --json)  AS_JSON=1 ;;
    -h|--help) sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "list-spaces: unknown option: $a (try --help)" >&2; exit 2 ;;
  esac
done

[ -d "$SPACES" ] || { echo "list-spaces: no spaces/ yet"; exit 0; }

field() { grep -m1 "^$2:" "$1" 2>/dev/null | cut -d: -f2- | sed 's/^ *//;s/ *$//'; }

rows=()
for d in "$SPACES"/*/; do
  [ -f "$d/index.md" ] || continue
  slug="$(basename "$d")"
  idx="$d/index.md"
  rel="$(field "$idx" relation)"
  # A readable name, but only where there is nothing to hide. `display` is
  # refused on a confidential space by check-space-boundary, so pairing it with
  # the slug here can never leak an owner: a space that has one has already
  # declared it is not confidential.
  disp="$(field "$idx" display)"
  conf="$(field "$idx" confidential)"
  [ "$conf" = "true" ] && disp=""
  label="$slug"
  [ -n "$disp" ] && label="$disp ($slug)"
  sid="$(field "$idx" space-id)"
  notes="$(find "$d" -name '*.md' -not -path '*/.git/*' | wc -l | tr -d ' ')"
  # Ahead of its own remote = confidential work that exists in one place only.
  if [ -d "$d/.git" ]; then
    ahead="$(git -C "$d" rev-list --count '@{u}..HEAD' 2>/dev/null || echo '-')"
    dirty="$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    url="$(git -C "$d" remote get-url origin 2>/dev/null || true)"
    if [ -n "$url" ]; then
      # host only: the repo name usually repeats the slug, and a non-neutral
      # slug would then leak through this listing too.
      remote="$(printf '%s' "$url" | sed -E 's#^[a-z]+://##; s#^[^@]*@##; s#[/:].*##')"
    else
      remote="none"
    fi
  else
    ahead="-"; dirty="-"; remote="not a repo"
  fi
  # The slug is neutral only when it does not spell the owner out. The
  # space-id-derived form is what a generated slug looks like.
  neutral="yes"
  if [ "${slug#sp-}" = "$slug" ]; then
    # The passport already carries the neutral form; only the directory
    # still spells the owner out. Name it, so the fix is obvious.
    neutral="NO"; [ -n "$sid" ] && neutral="-> sp-${sid%%-*}"
  fi
  owner=""; [ "$SHOW_OWNER" = "1" ] && owner="$(field "$idx" owner | tr -d '"')"
  rows+=("$label|$rel|$notes|$ahead|$dirty|$neutral|$remote|$owner")
done

if [ "${#rows[@]}" -eq 0 ]; then echo "list-spaces: no spaces"; exit 0; fi

if [ "$AS_JSON" = "1" ]; then
  printf '[\n'
  for i in "${!rows[@]}"; do
    IFS='|' read -r s r n a d ne rem ow <<< "${rows[$i]}"
    printf '  {"slug":"%s","relation":"%s","notes":%s,"ahead":"%s","dirty":"%s","neutral_slug":"%s","remote":"%s"' \
      "$s" "$r" "$n" "$a" "$d" "$ne" "$rem"
    [ -n "$ow" ] && printf ',"owner":"%s"' "$ow"
    printf '}%s\n' "$([ "$i" -lt "$((${#rows[@]}-1))" ] && echo ,)"
  done
  printf ']\n'
  exit 0
fi

printf '%-30s %-16s %6s %6s %6s %14s  %s\n' SPACE RELATION NOTES AHEAD DIRTY NEUTRAL BACKUP-HOST
for r in "${rows[@]}"; do
  IFS='|' read -r s rel n a d ne rem ow <<< "$r"
  printf '%-30s %-16s %6s %6s %6s %14s  %s\n' "$s" "${rel:--}" "$n" "$a" "$d" "$ne" "$rem"
  [ -n "$ow" ] && printf '%-30s owner: %s\n' "" "$ow"
done

echo
echo "AHEAD > 0 means confidential work exists only on this machine — run: scripts/sync/sync-space.sh <slug>"
echo "NEUTRAL names the slug this space would have if generated; the current one spells the owner out."
[ "$SHOW_OWNER" = "0" ] && echo "Owner names are withheld; pass --owner to print them."
