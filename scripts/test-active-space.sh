#!/usr/bin/env bash
# test-active-space.sh — proves the "active space" session mode:
#   - active-space.sh use/show/clear round-trips through the local/.active-space marker
#   - env AGENTBRAIN_SPACE overrides the marker (env wins)
#   - invalid slugs are rejected; use requires the space to exist
#   - the marker is gitignored (never synced)
#   - new-note.sh (no --space) defaults into the active space; cleared = normal location
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AS="$ROOT_DIR/scripts/active-space.sh"
LOCAL_DIR="$ROOT_DIR/local"
MARKER="$LOCAL_DIR/.active-space"
SLUG="__astest__"
# One consistent input for both runs: active redirects it into the space; cleared
# leaves it at its normal vault location.
NOTE_REL="local/learnings/__astest_normal__"
SPACE_NOTE="$LOCAL_DIR/spaces/$SLUG/learnings/__astest_normal__.md"
NORMAL_NOTE="$LOCAL_DIR/learnings/__astest_normal__.md"

# Preserve any real active-space marker so the test never clobbers a live session.
BACKUP=""
if [ -f "$MARKER" ]; then BACKUP="$(mktemp)"; cp "$MARKER" "$BACKUP"; fi
cleanup() {
	rm -rf "$LOCAL_DIR/spaces/$SLUG"
	rm -f "$NORMAL_NOTE"
	if [ -n "$BACKUP" ]; then cp "$BACKUP" "$MARKER"; rm -f "$BACKUP"; else rm -f "$MARKER"; fi
}
trap cleanup EXIT

# A space must exist before it can be activated.
mkdir -p "$LOCAL_DIR/spaces/$SLUG/learnings"

# 1) use writes the marker; show returns the active slug.
bash "$AS" use "$SLUG" >/dev/null 2>&1 || { echo "FAIL: 'use $SLUG' exited non-zero"; exit 1; }
[ -f "$MARKER" ] || { echo "FAIL: marker not written at $MARKER"; exit 1; }
got="$(bash "$AS" show 2>/dev/null)"
[ "$got" = "$SLUG" ] || { echo "FAIL: show returned '$got', want '$SLUG'"; exit 1; }
echo "PASS use+show"

# 2) env AGENTBRAIN_SPACE overrides the marker (env wins).
got="$(AGENTBRAIN_SPACE=__astest_env__ bash "$AS" show 2>/dev/null)"
[ "$got" = "__astest_env__" ] || { echo "FAIL: env did not override marker (got '$got')"; exit 1; }
echo "PASS env-override"

# 3) invalid slugs are rejected and leave the marker untouched.
for bad in "../evil" "a/b" "" ".hidden"; do
	if bash "$AS" use "$bad" >/dev/null 2>&1; then
		echo "FAIL: invalid slug accepted: '$bad'"; exit 1
	fi
done
[ "$(bash "$AS" show 2>/dev/null)" = "$SLUG" ] || { echo "FAIL: marker changed by rejected slug"; exit 1; }
# use of a non-existent space must fail.
if bash "$AS" use "__astest_missing__" >/dev/null 2>&1; then
	echo "FAIL: 'use' accepted a non-existent space"; exit 1
fi
echo "PASS slug-guard"

# 4) the marker must be gitignored (so it is never synced).
if git -C "$LOCAL_DIR" rev-parse --git-dir >/dev/null 2>&1; then
	git -C "$LOCAL_DIR" check-ignore -q .active-space || { echo "FAIL: .active-space not gitignored"; exit 1; }
	echo "PASS gitignored"
else
	echo "SKIP gitignored: local/ is not a git repo"
fi

# 5) with an active space set, new-note (no --space) lands inside it, with a
#    path-correct id matching the real (spaced) write path.
bash "$AS" use "$SLUG" >/dev/null 2>&1
bash "$ROOT_DIR/scripts/new-note.sh" learning "$NOTE_REL" "Probe Active" >/dev/null 2>&1
[ -f "$SPACE_NOTE" ] || { echo "FAIL: active note not created at $SPACE_NOTE"; exit 1; }
grep -q "^space: $SLUG" "$SPACE_NOTE" || { echo "FAIL: active note missing 'space: $SLUG'"; exit 1; }
want="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "local/spaces/$SLUG/learnings/__astest_normal__")"
have="$(awk -F': ' '/^id:/{print $2; exit}' "$SPACE_NOTE")"
[ "$want" = "$have" ] || { echo "FAIL: active-note id parity want=$want have=$have"; exit 1; }
echo "PASS new-note-active"

# 6) cleared → the same invocation lands in the normal vault location.
bash "$AS" clear >/dev/null 2>&1
[ -f "$MARKER" ] && { echo "FAIL: clear did not remove marker"; exit 1; }
[ "$(bash "$AS" show 2>/dev/null)" = "none" ] || { echo "FAIL: show after clear is not 'none'"; exit 1; }
bash "$ROOT_DIR/scripts/new-note.sh" learning "$NOTE_REL" "Normal" >/dev/null 2>&1
[ -f "$NORMAL_NOTE" ] || { echo "FAIL: cleared note not created at normal location $NORMAL_NOTE"; exit 1; }
grep -q "^space:" "$NORMAL_NOTE" && { echo "FAIL: normal note unexpectedly carries a space field"; exit 1; }
echo "PASS new-note-normal"

echo "PASS test-active-space"
