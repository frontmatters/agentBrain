#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-enforcement.sh: a trap learning that claims a guard which is
# gone must fail, and so must a claim with nothing named, and so must a guard the
# coverage map does not link back. A declared guard that exists and is linked to its
# subject, and an honest `none`, must pass.
#
# The first case is the one worth having: a learning that says "a hook catches this" while
# the hook has been deleted is worse than no learning, because you stop watching for it.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CHECK="$ROOT_DIR/scripts/checks/check-enforcement.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/checks" "$TMP/scripts/lib" "$TMP/vault/learnings"
cp "$CHECK" "$TMP/scripts/checks/"
# The check asserts its vault through the lib, so the fixture needs it: without
# it the sourcing fails under set -e and every arm below reports the wrong thing.
cp "$ROOT_DIR/scripts/lib/vault.sh" "$TMP/scripts/lib/"
cd "$TMP" || exit 1
printf '{"unclassified": 99}\n' > scripts/checks/.enforcement-ratchet.json

write_learning() { # write_learning <frontmatter lines>
	{ echo "---"; echo "date: 2026-01-01"; echo "type: learning"; echo "tags: [gotcha]"
	  printf '%s\n' "$@"; echo "id: 00000000-0000-5000-8000-000000000000"; echo "---"
	  echo; echo "# Trap"; } > vault/learnings/trap.md
}

write_learning "enforcement: hook" "enforced_by: scripts/gone.py"
if bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement accepted a guard that does not exist" >&2; exit 1
fi

write_learning "enforcement: hook"
if bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement accepted a claim naming no guard" >&2; exit 1
fi

write_learning "enforcement: something-random"
if bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement accepted an unknown enforcement value" >&2; exit 1
fi

mkdir -p scripts vault/config
# The guard has to be linked back to its subject: rule A checks the claim in both
# directions, so a file that merely exists is not enough once a coverage map exists.
printf '#!/bin/sh\n' > scripts/exists.py
printf 'scripts/other.py\ttrap\n' > vault/config/enforcement-covers.tsv
write_learning "enforcement: hook" "enforced_by: scripts/exists.py"
if bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement accepted a guard the coverage map does not link" >&2; exit 1
fi
printf 'scripts/exists.py\ttrap\n' > vault/config/enforcement-covers.tsv
if ! bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement rejected a guard that does exist" >&2; exit 1
fi

write_learning "enforcement: none"
if ! bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: check-enforcement rejected an honest 'none'" >&2; exit 1
fi

echo "negative case holds: check-enforcement rejects a claimed guard that is missing"
