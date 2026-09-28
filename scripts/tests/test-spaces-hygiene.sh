#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-spaces-hygiene.sh — type:space passports pass validate-note-id + check-vault-content.
#
# Regression test for the spaces feature: scaffolded space passports
# (local/spaces/<slug>/index.md, frontmatter `type: space` + path-derived `id:`)
# must keep validating like any other note, so spaces stay hygienic.
#   - validate-note-id.sh : id/path uuid5 parity (path-based, type-agnostic)
#   - check-vault-content.sh local/spaces : frontmatter/id/wiki-link checks, scoped
#     (scope is a positional arg — there is no --scope flag; see the script's parser)
#
# It runs against a throwaway vault with freshly scaffolded spaces, never the
# user's own vault: this tests what the framework writes, not a user's notes.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
TV="$(mktemp -d)"; export AGENTBRAIN_VAULT="$TV"
trap 'rm -rf "$TV"' EXIT
for slug in __hyg-client__ __hyg-employer__; do
	bash "$ROOT_DIR/scripts/new-space.sh" "$slug" --owner "Test Owner" --relation client >/dev/null 2>&1 \
		|| { echo "FAIL: new-space could not scaffold $slug"; exit 1; }
done
SPACES_DIR="$TV/spaces"

# Validate id/path parity for every space passport (spaces/<slug>/index.md).
while IFS= read -r P; do
	[ -n "$P" ] || continue
	bash "$ROOT_DIR/scripts/hooks/validate-note-id.sh" "$P" \
		|| { echo "FAIL: validate-note-id rejects $P"; exit 1; }
done < <(find "$SPACES_DIR" -mindepth 2 -maxdepth 2 -name index.md 2>/dev/null)

# Frontmatter/id/wiki-link checks over the whole spaces tree (scope is positional).
bash "$ROOT_DIR/scripts/checks/check-vault-content.sh" local/spaces >/dev/null 2>&1 \
	|| { echo "FAIL: check-vault-content errors on the scaffolded spaces"; exit 1; }

echo "PASS test-spaces-hygiene"
