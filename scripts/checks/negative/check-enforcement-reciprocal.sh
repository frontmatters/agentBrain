#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for rule A of check-enforcement.sh: the coverage map in the
# vault must link a guard back to the learning that claims it. Without this,
# `enforced_by:` only proves a file exists, and `enforced_by: README.md` passes
# while guarding nothing.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/vault/learnings" "$TMP/vault/config" "$TMP/scripts/checks" "$TMP/scripts/lib"
cp "$ROOT_DIR/scripts/checks/check-enforcement.sh" "$TMP/scripts/checks/"
cp "$ROOT_DIR/scripts/lib/vault.sh" "$TMP/scripts/lib/"
printf '{ "unclassified": 99 }\n' > "$TMP/scripts/checks/.enforcement-ratchet.json"
printf 'not empty\n' > "$TMP/guard.sh"
cat > "$TMP/vault/learnings/nep.md" <<'NOTE'
---
date: 2026-09-23
type: learning
tags: [valkuil]
enforcement: gate
enforced_by: guard.sh
id: 00000000-0000-5000-8000-000000000000
---
# A trap nothing actually catches
NOTE

cd "$TMP" || exit 1

# A map that links the guard to another learning does not cover this one.
printf 'guard.sh\tsomething-else\n' > "$TMP/vault/config/enforcement-covers.tsv"
if bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: a guard the coverage map does not link to the learning was accepted" >&2
	exit 1
fi

# The same claim must pass once the map links it back.
printf '# guard -> learning\nguard.sh\tnep\n' > "$TMP/vault/config/enforcement-covers.tsv"
if ! bash scripts/checks/check-enforcement.sh >/dev/null 2>&1; then
	echo "NEGATIVE CASE FAILED: a reciprocal claim was rejected" >&2
	exit 1
fi

# No map at all: the back-link is not measured, which must say so, not fail.
rm "$TMP/vault/config/enforcement-covers.tsv"
if ! out="$(bash scripts/checks/check-enforcement.sh 2>&1)"; then
	echo "NEGATIVE CASE FAILED: a missing coverage map failed the check" >&2
	exit 1
fi
case "$out" in *"not measured"*) ;; *)
	echo "NEGATIVE CASE FAILED: a missing coverage map was not reported as not measured" >&2
	exit 1 ;;
esac

echo "negative case holds: check-enforcement requires the coverage map to link a guard to its subject"
