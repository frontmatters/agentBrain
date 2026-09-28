#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-new-note-space.sh — new-note.sh --space writes under local/spaces/<slug>/ with valid id,
# and rejects invalid slugs that would escape local/spaces/<slug>/ (path-escape guard).
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
SLUG="__nntest__"; REL="vault/spaces/$SLUG/learnings/probe"
trap 'rm -rf "$ROOT_DIR/vault/spaces/$SLUG"' EXIT

bash "$ROOT_DIR/scripts/new-note.sh" learning "learnings/probe" "Probe" --space "$SLUG" >/dev/null 2>&1
F="$ROOT_DIR/vault/spaces/$SLUG/learnings/probe.md"
[ -f "$F" ] || { echo "FAIL: file not created at $F"; exit 1; }
grep -q "^space: $SLUG" "$F" || { echo "FAIL: missing 'space: $SLUG' frontmatter"; exit 1; }
want="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "$REL")"
have="$(awk -F': ' '/^id:/{print $2; exit}' "$F")"
[ "$want" = "$have" ] || { echo "FAIL: id parity want=$want have=$have"; exit 1; }
echo "PASS test-new-note-space"

# A fully-qualified space path plus the same env context must normalize to one
# space root, never local/spaces/<slug>/spaces/<slug>/...
FULL_REL="vault/spaces/$SLUG/learnings/full-path"
AGENTBRAIN_CONTEXT="$SLUG" bash "$ROOT_DIR/scripts/new-note.sh" learning "$FULL_REL" "Full Path" >/dev/null 2>&1
[ -f "$ROOT_DIR/${FULL_REL}.md" ] || { echo "FAIL: full space path was not normalized"; exit 1; }
[ ! -e "$ROOT_DIR/vault/spaces/$SLUG/spaces" ] || { echo "FAIL: context + full path nested the space twice"; exit 1; }
echo "PASS test-new-note-space-full-path-normalization"

# Conflicting path and explicit context must fail before creating anything.
CONFLICT_REL="vault/spaces/$SLUG/learnings/conflict"
if AGENTBRAIN_CONTEXT="other" bash "$ROOT_DIR/scripts/new-note.sh" learning "$CONFLICT_REL" "Conflict" >/dev/null 2>&1; then
	echo "FAIL: conflicting path/context was accepted"; exit 1
fi
[ ! -e "$ROOT_DIR/${CONFLICT_REL}.md" ] || { echo "FAIL: conflicting path/context wrote a file"; exit 1; }
echo "PASS test-new-note-space-context-conflict"

# A full space path is also sufficient without an env/flag context.
PATH_ONLY_REL="vault/spaces/$SLUG/learnings/path-only"
env -u AGENTBRAIN_CONTEXT -u AGENTBRAIN_SPACE bash "$ROOT_DIR/scripts/new-note.sh" learning "$PATH_ONLY_REL" "Path Only" >/dev/null 2>&1
[ -f "$ROOT_DIR/${PATH_ONLY_REL}.md" ] || { echo "FAIL: path-only space route was not created"; exit 1; }
echo "PASS test-new-note-space-path-only"

# invalid slugs must be rejected (no path-escape, non-zero exit, no file written)
for bad in "../personal" "a/b" ""; do
	if bash "$ROOT_DIR/scripts/new-note.sh" learning "learnings/x" "X" --space "$bad" >/dev/null 2>&1; then
		echo "FAIL: invalid slug accepted: '$bad'"; exit 1
	fi
done
# ensure no escape artifact was written outside local/spaces/
[ ! -e "$ROOT_DIR/vault/personal" ] || { echo "FAIL: path-escape created local/personal"; exit 1; }
[ ! -e "$ROOT_DIR/vault/learnings/x.md" ] || { echo "FAIL: rejected slug still wrote local/learnings/x.md"; exit 1; }
echo "PASS test-new-note-space-slug-guard"
