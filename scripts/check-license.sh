#!/usr/bin/env bash
# Check the repo's license is declared consistently everywhere: every own LICENSE
# file, every own package.json SPDX field, the README license section, and that
# the addon packager bundles the LICENSE. Guards against license drift — e.g. a
# stray BSL/MIT file or SPDX field left behind after a relicense.
#
# On a relicense, update the three EXPECTED_* values below — that is the single
# source of truth this check enforces across the tree.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# ── Expected license (single source of truth) ──
EXPECTED_SPDX="Apache-2.0"
EXPECTED_BODY_MARK="Apache License"     # must appear in every own LICENSE file
EXPECTED_README_MARK="Apache License 2.0"

fail=()

# 1. Every own LICENSE file carries the expected license text (skip bundled deps).
while IFS= read -r lic; do
	[[ -z "$lic" ]] && continue
	if ! grep -q "$EXPECTED_BODY_MARK" "$lic"; then
		fail+=("LICENSE not $EXPECTED_SPDX: $lic")
	fi
done < <(git ls-files | grep -E '(^|/)LICENSE$' | grep -v '/node_modules/' || true)

# 2. Every own package.json SPDX field matches (skip bundled deps).
while IFS= read -r pj; do
	[[ -z "$pj" ]] && continue
	spdx="$(grep -m1 '"license"' "$pj" | sed -E 's/.*"license"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"
	if [[ -n "$spdx" && "$spdx" != "$EXPECTED_SPDX" ]]; then
		fail+=("package.json license '$spdx' != $EXPECTED_SPDX: $pj")
	fi
done < <(git ls-files | grep -E '(^|/)package\.json$' | grep -v '/node_modules/' || true)

# 3. README license section names the expected license.
if [[ -f README.md ]] && ! grep -q "$EXPECTED_README_MARK" README.md; then
	fail+=("README.md does not mention '$EXPECTED_README_MARK' under ## License")
fi

# 4. Addon packager bundles the LICENSE (else standalone addon zips are
#    rights-ambiguous — see local/learnings/package-scripts-must-bundle-license).
if [[ -f scripts/package-addon.sh ]] && ! grep -qE 'cp .*LICENSE' scripts/package-addon.sh; then
	fail+=("scripts/package-addon.sh does not bundle LICENSE into addon packages")
fi

# 5. No leftover BSL/BUSL markers in the public layer.
if drift="$(grep -rniE --include='*.md' --include='*.json' --include='*.sh' \
	--exclude-dir=.git --exclude-dir=local --exclude-dir=node_modules \
	--exclude=check-license.sh \
	'business source|BUSL-1\.1|BSL 1\.1' . 2>/dev/null)"; then
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		fail+=("stray BSL/BUSL ref: $line")
	done <<<"$drift"
fi

if ((${#fail[@]} > 0)); then
	printf 'License check failed (expected %s):\n' "$EXPECTED_SPDX" >&2
	printf '  %s\n' "${fail[@]}" >&2
	exit 1
fi

printf 'License check passed (%s consistent across LICENSE files, package.json, README, packager).\n' "$EXPECTED_SPDX"
