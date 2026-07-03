#!/usr/bin/env bash
# test-spaces-hygiene.sh — type:space paspoorten pass validate-note-id + check-local-content.
#
# Regression test for the spaces feature: scaffolded space paspoorten
# (local/spaces/<slug>/index.md, frontmatter `type: space` + path-derived `id:`)
# must keep validating like any other note, so spaces stay hygienic.
#   - validate-note-id.sh : id/path uuid5 parity (path-based, type-agnostic)
#   - check-local-content.sh local/spaces : frontmatter/id/wiki-link checks, scoped
#     (scope is a positional arg — there is no --scope flag; see the script's parser)
#
# Space slugs are discovered dynamically (not hardcoded): the slugs are private
# customer/employer names on the privacy denylist, so a public script must not
# name them. This also makes the test cover every current and future space.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPACES_DIR="$ROOT_DIR/local/spaces"

[ -d "$SPACES_DIR" ] || { echo "PASS test-spaces-hygiene (no spaces)"; exit 0; }

# Validate id/path parity for every space paspoort (local/spaces/<slug>/index.md).
while IFS= read -r P; do
	[ -n "$P" ] || continue
	bash "$ROOT_DIR/scripts/validate-note-id.sh" "$P" \
		|| { echo "FAIL: validate-note-id rejects $P"; exit 1; }
done < <(find "$SPACES_DIR" -mindepth 2 -maxdepth 2 -name index.md 2>/dev/null)

# Frontmatter/id/wiki-link checks over the whole spaces tree (scope is positional).
bash "$ROOT_DIR/scripts/check-local-content.sh" local/spaces >/dev/null 2>&1 \
	|| { echo "FAIL: check-local-content errors on local/spaces"; exit 1; }

echo "PASS test-spaces-hygiene"
