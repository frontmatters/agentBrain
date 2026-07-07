#!/usr/bin/env bash
# check-version.sh — Validate that VERSION exists and parses as agentBrain SemVer.
#
# Format: X.Y.Z optionally followed by -prerelease-NN
# Examples that pass:
#   1.0.0
#   1.5.6
#   1.6.0-prerelease-01
#   2.0.0-prerelease-12
# Legacy slug form (1.6.0-prerelease-addon-registry-02) is still accepted so an
# old VERSION validates until the next bump rewrites it to the clean form.
#
# Bumped by scripts/bump-version.sh — see that script for write-side enforcement.
# This script is the read-side validator wired into doctor.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"

if [ ! -f "$VERSION_FILE" ]; then
	echo "check-version: VERSION file missing at $VERSION_FILE" >&2
	echo "  Fix: scripts/bump-version.sh patch  (or create the file with an initial X.Y.Z)" >&2
	exit 1
fi

# Read exactly the first line; default IFS strips leading/trailing whitespace;
# -r preserves backslashes. NOT tr -d '[:space:]' (would smash multi-line
# input AND silently "fix" malformed versions like '1. 2.3' to '1.2.3').
read -r VERSION < "$VERSION_FILE" || true
VERSION="${VERSION%$'\r'}"  # strip trailing CR for DOS line endings

if [ -z "$VERSION" ]; then
	echo "check-version: VERSION file is empty" >&2
	exit 1
fi

# Reject multi-line VERSION files as malformed (catches accidental concatenation).
if [ "$(wc -l < "$VERSION_FILE")" -gt 1 ]; then
	echo "check-version: VERSION must be a single line (found multiple lines in $VERSION_FILE)" >&2
	exit 1
fi

# Accept: X.Y.Z  or  X.Y.Z-prerelease-NN  (the optional slug group keeps legacy
# tags valid; bump-version.sh only ever writes the clean, slug-less form).
if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-prerelease-([a-z0-9][a-z0-9-]*-)?[0-9]+)?$ ]]; then
	echo "check-version: ✅ VERSION=$VERSION is valid agentBrain SemVer"
	exit 0
fi

echo "check-version: ❌ VERSION='$VERSION' does not match agentBrain SemVer format" >&2
echo "  Expected: X.Y.Z  or  X.Y.Z-prerelease-NN" >&2
echo "  Fix:      scripts/bump-version.sh --show     (inspect current)" >&2
echo "            scripts/bump-version.sh patch      (clean bump)" >&2
exit 1
