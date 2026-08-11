#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-new-space.sh — new-space.sh scaffolds a valid, hygienic space paspoort and
# rejects bad input (invalid slug / missing owner|relation / overwrite).
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLUG="__nstest__"; REL="local/spaces/$SLUG/index"
trap 'rm -rf "$ROOT_DIR/local/spaces/$SLUG"' EXIT

bash "$ROOT_DIR/scripts/new-space.sh" "$SLUG" --owner "Test Owner" --relation client >/dev/null 2>&1
F="$ROOT_DIR/local/spaces/$SLUG/index.md"
[ -f "$F" ] || { echo "FAIL: paspoort not created at $F"; exit 1; }
grep -q "^type: space" "$F" || { echo "FAIL: missing 'type: space'"; exit 1; }
grep -qE "^space-id: [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" "$F" \
	|| { echo "FAIL: missing/invalid space-id"; exit 1; }

# id must equal uuid5-gen of the paspoort path (the note-schema invariant).
want="$(bash "$ROOT_DIR/scripts/uuid5-gen.sh" "$REL")"
have="$(awk -F': ' '/^id:/{print $2; exit}' "$F")"
[ "$want" = "$have" ] || { echo "FAIL: id parity want=$want have=$have"; exit 1; }

# Must survive the same hygiene check doctor runs over spaces.
bash "$ROOT_DIR/scripts/check-local-content.sh" "local/spaces/$SLUG" >/dev/null 2>&1 \
	|| { echo "FAIL: check-local-content rejects the scaffolded space"; exit 1; }

# Refuse to overwrite an existing paspoort.
if bash "$ROOT_DIR/scripts/new-space.sh" "$SLUG" --owner X --relation client >/dev/null 2>&1; then
	echo "FAIL: overwrote existing paspoort"; exit 1
fi
echo "PASS test-new-space"

# Invalid slugs must be rejected with no path-escape.
for bad in "../personal" "a/b" ""; do
	if bash "$ROOT_DIR/scripts/new-space.sh" "$bad" --owner X --relation client >/dev/null 2>&1; then
		echo "FAIL: invalid slug accepted: '$bad'"; exit 1
	fi
done
[ ! -e "$ROOT_DIR/local/personal" ] || { echo "FAIL: path-escape created local/personal"; exit 1; }

# Missing required flags must fail.
if bash "$ROOT_DIR/scripts/new-space.sh" "__nsx__" --relation client >/dev/null 2>&1; then
	echo "FAIL: accepted missing --owner"; rm -rf "$ROOT_DIR/local/spaces/__nsx__"; exit 1
fi
if bash "$ROOT_DIR/scripts/new-space.sh" "__nsx__" --owner X >/dev/null 2>&1; then
	echo "FAIL: accepted missing --relation"; rm -rf "$ROOT_DIR/local/spaces/__nsx__"; exit 1
fi
echo "PASS test-new-space-guards"
