#!/usr/bin/env bash
# test-new-note-space.sh — new-note.sh --space writes under local/spaces/<slug>/ with valid id,
# and rejects invalid slugs that would escape local/spaces/<slug>/ (path-escape guard).
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLUG="__nntest__"; REL="local/spaces/$SLUG/learnings/probe"
trap 'rm -rf "$ROOT_DIR/local/spaces/$SLUG"' EXIT

bash "$ROOT_DIR/scripts/new-note.sh" learning "learnings/probe" "Probe" --space "$SLUG" >/dev/null 2>&1
F="$ROOT_DIR/local/spaces/$SLUG/learnings/probe.md"
[ -f "$F" ] || { echo "FAIL: file not created at $F"; exit 1; }
grep -q "^space: $SLUG" "$F" || { echo "FAIL: missing 'space: $SLUG' frontmatter"; exit 1; }
want="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "$REL")"
have="$(awk -F': ' '/^id:/{print $2; exit}' "$F")"
[ "$want" = "$have" ] || { echo "FAIL: id parity want=$want have=$have"; exit 1; }
echo "PASS test-new-note-space"

# invalid slugs must be rejected (no path-escape, non-zero exit, no file written)
for bad in "../personal" "a/b" ""; do
	if bash "$ROOT_DIR/scripts/new-note.sh" learning "learnings/x" "X" --space "$bad" >/dev/null 2>&1; then
		echo "FAIL: invalid slug accepted: '$bad'"; exit 1
	fi
done
# ensure no escape artifact was written outside local/spaces/
[ ! -e "$ROOT_DIR/local/personal" ] || { echo "FAIL: path-escape created local/personal"; exit 1; }
[ ! -e "$ROOT_DIR/local/learnings/x.md" ] || { echo "FAIL: rejected slug still wrote local/learnings/x.md"; exit 1; }
echo "PASS test-new-note-space-slug-guard"
