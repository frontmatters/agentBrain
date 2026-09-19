#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-enforcement.sh: a trap learning that claims a guard which is
# gone must fail, and so must a claim with nothing named. A declared guard that exists,
# and an honest `none`, must pass.
#
# The first case is the one worth having: a learning that says "a hook catches this" while
# the hook has been deleted is worse than no learning, because you stop watching for it.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECK="$ROOT_DIR/scripts/checks/check-enforcement.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/checks" "$TMP/vault/learnings"
cp "$CHECK" "$TMP/scripts/checks/"
cd "$TMP" || exit 1
printf '{"unclassified": 99}\n' > scripts/checks/.enforcement-ratchet.json

leer() { # leer <regels frontmatter>
	{ echo "---"; echo "date: 2026-01-01"; echo "type: learning"; echo "tags: [gotcha]"
	  printf '%s\n' "$@"; echo "id: 00000000-0000-5000-8000-000000000000"; echo "---"
	  echo; echo "# Val"; } > vault/learnings/val.md
}

leer "enforcement: hook" "enforced_by: scripts/deze-is-weg.py"
if bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement accepted a guard that does not exist" >&2; exit 1
fi

leer "enforcement: hook"
if bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement accepted a claim naming no guard" >&2; exit 1
fi

leer "enforcement: zomaar-iets"
if bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement accepted an unknown enforcement value" >&2; exit 1
fi

mkdir -p scripts
printf '#!/bin/sh\n' > scripts/bestaat.py
leer "enforcement: hook" "enforced_by: scripts/bestaat.py"
if ! bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement rejected a guard that does exist" >&2; exit 1
fi

leer "enforcement: none"
if ! bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement rejected an honest 'none'" >&2; exit 1
fi

echo "negative case holds: check-enforcement rejects a claimed guard that is missing"
