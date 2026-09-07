#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-product-notes.sh.
#
# The check must reject a kind: value outside product|experiment|fork. Its first
# version could not have caught this: find without -L returned zero files over a
# symlinked vault, so it reported "passed" after reading nothing at all.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECK="$ROOT_DIR/scripts/checks/check-product-notes.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/vault/projects/bad"
cat > "$TMP/vault/projects/bad/index.md" <<'M'
---
date: 2026-09-06
type: project
kind: prodcut
status: active
---
M

# The check resolves its root from its own location, so run it against a copy.
mkdir -p "$TMP/scripts/checks"
cp "$CHECK" "$TMP/scripts/checks/"
cd "$TMP" || exit 1

if bash scripts/checks/check-product-notes.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-product-notes accepted kind: prodcut" >&2
	exit 1
fi

# And a product with no channels: nothing to check is not the same as nothing wrong.
cat > "$TMP/vault/projects/bad/index.md" <<'M'
---
date: 2026-09-06
type: project
kind: product
status: active
---
M
if bash scripts/checks/check-product-notes.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: accepted kind: product with no publishes list" >&2
	exit 1
fi

echo "negative/check-product-notes: 2 rejection(s) confirmed"
