#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-nda-redaction.sh — the report must not print what the gate protects.
#
# check-nda closed with the line "Marker names are not printed", and it was
# true of the markers and false of everything else: it printed paths, and a
# path like projects/<owner>-page-builder-poc carries the name as plainly as
# the marker does. It printed the space slug as a heading too, which on this
# machine is the owner name for three of six spaces.
#
# So the property under test is not "the marker is withheld". It is that the
# owner name does not appear ANYWHERE in the output, by any route.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CHECK="$ROOT/scripts/checks/check-nda.sh"
fail=0
ok() { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
VAULT="$TMP/vault"
NAME="Zwartkamp"   # a fake owner, distinctive enough that a substring hit is real

mkdir -p "$VAULT/spaces/$NAME/notes" "$VAULT/projects/$NAME-portal" "$VAULT/learnings"
cat > "$VAULT/spaces/$NAME/index.md" <<EOF
---
type: space
slug: $NAME
space-id: 7c9f21ab-0000-4000-8000-000000000001
owner: "$NAME"
confidential: true
---
EOF
printf -- '---\ntype: learning\n---\n\nnotes about %s and their stack\n' "$NAME" \
	> "$VAULT/learnings/stack.md"
printf -- '---\ntype: project\n---\n\nplan\n' > "$VAULT/projects/$NAME-portal/index.md"

git -C "$VAULT" init -q .
git -C "$VAULT" add -A >/dev/null 2>&1
git -C "$VAULT" -c user.email=t@t -c user.name=t commit -qm seed >/dev/null 2>&1

out="$(BRAIN_DIR="$TMP" bash "$CHECK" 2>&1)"

case "$out" in
*FAILED*) ok "detects" "an owner name outside its space is still detected" ;;
*) bad "detects" "the gate stopped detecting anything" ;;
esac

case "$out" in
*"$NAME"*)
	bad "redacted" "the owner name appears in the report"
	printf '%s\n' "$out" | grep -n "$NAME" | sed 's/^/        /' >&2
	;;
*) ok "redacted" "the owner name appears nowhere in the report" ;;
esac

case "$out" in
*sp-7c9f21ab*) ok "handle" "the space is named by its opaque id instead" ;;
*) bad "handle" "the report has no usable handle for the space" ;;
esac

# --list prints every path, which is the mode most likely to leak.
out="$(BRAIN_DIR="$TMP" bash "$CHECK" --list 2>&1)"
case "$out" in
*"$NAME"*) bad "redacted-list" "--list prints the owner name" ;;
*) ok "redacted-list" "--list stays redacted too" ;;
esac

# A test-fixture passport (__name__) must not become a marker source: its
# invented owner appears in the test scripts themselves.
mkdir -p "$VAULT/spaces/__fixture__"
printf -- '---\ntype: space\nslug: __fixture__\nspace-id: 7c9f21ab-0000-4000-8000-000000000002\nowner: "Zwartkamp"\n---\n' > "$VAULT/spaces/__fixture__/index.md"
rm -rf "$VAULT/spaces/$NAME"
git -C "$VAULT" add -A >/dev/null 2>&1; git -C "$VAULT" -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null 2>&1
out="$(BRAIN_DIR="$TMP" bash "$CHECK" 2>&1)"
case "$out" in
*FAILED*) bad "fixture-ignored" "a __fixture__ passport was used as a marker source" ;;
*) ok "fixture-ignored" "a __name__ fixture passport is ignored" ;;
esac

if [ "$fail" -eq 0 ]; then
	echo "PASS test-nda-redaction"
else
	echo "FAIL test-nda-redaction" >&2
	exit 1
fi
