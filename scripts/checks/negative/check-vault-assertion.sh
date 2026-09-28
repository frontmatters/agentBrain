#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-vault-assertion.sh: a NEW check that reads the vault
# without asserting it must be refused, and one that asserts it must not be
# counted. Pinning both directions, because a ratchet you have only seen pass is
# a ratchet you do not know is on.
#
# The third case is the one worth having: a check that only MENTIONS the vault in
# a comment must not be counted, or the guard fires on prose and everyone learns
# to ignore it.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/checks"
cp "$ROOT_DIR/scripts/checks/check-vault-assertion.sh" "$TMP/scripts/checks/"
cd "$TMP" || exit 1
printf '{"unasserted": 0}\n' > scripts/checks/.vault-assertion-ratchet.json

# 1. a vault-reading check with no assertion pushes the count past the ceiling
printf '#!/bin/sh\nfind "$VAULT_DIR/learnings" -name "*.md"\n' > scripts/checks/check-nieuw.sh
if bash scripts/checks/check-vault-assertion.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: an unasserted vault-reading check was accepted" >&2; exit 1
fi

# 2. the same check, now asserting, is not counted
printf '#!/bin/sh\nvault_required check-nieuw || exit $?\nfind "$VAULT_DIR/learnings" -name "*.md"\n' > scripts/checks/check-nieuw.sh
if ! bash scripts/checks/check-vault-assertion.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: a check that calls vault_required was still counted" >&2; exit 1
fi

# 3. a comment-only mention is prose, not a read
printf '#!/bin/sh\n# this one explains vault/learnings and reads nothing\necho hoi\n' > scripts/checks/check-nieuw.sh
if ! bash scripts/checks/check-vault-assertion.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: a comment-only mention of the vault was counted as a read" >&2; exit 1
fi

echo "negative case holds: check-vault-assertion refuses a new unasserted vault reader"
