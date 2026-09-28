#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-spec-version.sh — Validate SemVer in spec-type frontmatter.
#
# Scans every SPEC*.md under vault/ (vault/skills/*/SPEC.md and any other
# spec-type markdown there).
# For each file: if a `version:` frontmatter field is present, verify it matches X.Y.Z SemVer.
# Specs without a `version:` field are NOT flagged (backward-compat for pre-v1.3 SPECs).
#
# Format: simple SemVer X.Y.Z. No prerelease suffix — specs iterate, they don't release.
# agentBrain framework itself uses fuller SemVer with prerelease (see scripts/checks/check-version.sh);
# this is a different concept and intentionally simpler.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR"
# shellcheck source=scripts/lib/vault.sh
. "$ROOT_DIR/scripts/lib/vault.sh"
vault_required check-spec-version "$VAULT_DIR" || exit $?

# Find all candidate spec files under vault/: SPEC.md or SPEC*.md at any depth.
# Use find -print0 + read -d '' for NUL-safety per the agent-agnostic patterns.
fail=0
checked=0
with_version=0

while IFS= read -r -d '' file; do
	checked=$((checked + 1))

	# Confirm it's a spec-type note by inspecting frontmatter (first 20 lines).
	type_field="$(awk 'NR>20{exit} /^type:[[:space:]]/{sub(/^type:[[:space:]]+/, ""); gsub(/[[:space:]]+$/, ""); print; exit}' "$file" 2>/dev/null || true)"
	if [ "$type_field" != "spec" ]; then
		continue
	fi

	# Extract version field if present.
	version_field="$(awk 'NR>20{exit} /^version:[[:space:]]/{sub(/^version:[[:space:]]+/, ""); gsub(/[[:space:]]+$/, ""); print; exit}' "$file" 2>/dev/null || true)"

	# Backward-compat: spec without `version:` is OK (not flagged).
	if [ -z "$version_field" ]; then
		continue
	fi

	with_version=$((with_version + 1))

	if [[ "$version_field" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		continue
	fi

	echo "check-spec-version: ❌ $file" >&2
	echo "  version: '$version_field' does not match X.Y.Z SemVer" >&2
	echo "  Fix: edit the frontmatter to e.g. 'version: 1.0.0' (no prerelease suffix)" >&2
	fail=1
done < <(find "$VAULT_DIR/" -type f \( -name 'SPEC.md' -o -name 'SPEC*.md' \) -print0 2>/dev/null)

if [ "$fail" -ne 0 ]; then
	exit 1
fi

echo "check-spec-version: ✅ $checked spec(s) scanned, $with_version with version field, all valid"
exit 0
