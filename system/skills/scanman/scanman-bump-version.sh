#!/usr/bin/env bash
# scanman-bump-version.sh — bump the scanman method version (VERSION file).
#
# Semver: pre-1.0 we live in 0.0.x. Default bump is `patch` (last digit + 1).
# A `minor` bump increments the middle digit and resets patch to 0.
#
# Usage:
#   scanman-bump-version.sh [--show | patch | minor]
#   scanman-bump-version.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_scanman-lib.sh
. "${SCRIPT_DIR}/_scanman-lib.sh"

VERSION_FILE="${SCRIPT_DIR}/VERSION"

usage() {
    cat <<'EOF'
scanman-bump-version.sh — bump the scanman method version

USAGE:
  scanman-bump-version.sh [--show | patch | minor]
  scanman-bump-version.sh --help

COMMANDS:
  --show              Print current version and exit.
  patch               Bump patch digit (0.0.5 -> 0.0.6). Default.
  minor               Bump minor digit (0.0.5 -> 0.1.0).
  --help, -h          Show this help.

FILES:
  VERSION             Plain-text version file (single line).

NOTE:
  Pre-1.0 the contract per SKILL.md §Versioning is:
    - stay in 0.0.x until method+templates+scripts are operationally stable
    - bump on any material change to SKILL.md, CHANGELOG.md, templates/, scripts/
EOF
}

if [ ! -f "$VERSION_FILE" ]; then
    die "VERSION file not found at: $VERSION_FILE"
fi

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"
if ! [[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    die "VERSION file does not contain a valid semver: '$CURRENT'"
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

CMD="${1:-patch}"

case "$CMD" in
    --help|-h)
        usage
        exit 0
        ;;
    --show|show)
        echo "$CURRENT"
        exit 0
        ;;
    patch)
        NEW="${MAJOR}.${MINOR}.$((PATCH + 1))"
        ;;
    minor)
        NEW="${MAJOR}.$((MINOR + 1)).0"
        ;;
    major)
        die "major bump not allowed pre-1.0 — stay in 0.0.x per SKILL.md §Versioning"
        ;;
    *)
        echo "ERROR: unknown command: $CMD" >&2
        echo "" >&2
        usage >&2
        exit 2
        ;;
esac

echo "$NEW" > "$VERSION_FILE"
echo "scanman version: $CURRENT -> $NEW"
echo "Next: update CHANGELOG.md with the rationale for the bump."
