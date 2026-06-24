#!/usr/bin/env bash
set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCANMAN_DIR="$AGENTBRAIN_DIR/system/skills/scanman"
VERSION_FILE="$SCANMAN_DIR/VERSION"
CHANGELOG_FILE="$SCANMAN_DIR/CHANGELOG.md"

usage() {
  echo "Usage:" >&2
  echo "  bash scripts/scanman-release.sh check" >&2
  echo "  bash scripts/scanman-release.sh current" >&2
  echo "  bash scripts/scanman-release.sh release <0.0.x>" >&2
}

current_version() {
  tr -d '[:space:]' < "$VERSION_FILE"
}

require_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Not a valid semver version: $version" >&2
    exit 1
  fi
}

check() {
  local version
  version="$(current_version)"
  require_version "$version"
  grep -q "## $version" "$CHANGELOG_FILE" || {
    echo "Missing changelog entry for $version" >&2
    exit 1
  }
  echo "Scanman release check OK"
  echo "Current version: $version"
}

release() {
  local version="$1"
  require_version "$version"
  echo "$version" > "$VERSION_FILE"
  echo "Updated Scanman version to $version"
  echo "Remember to add/update: $CHANGELOG_FILE"
}

cmd="${1:-}"
case "$cmd" in
  check)
    check
    ;;
  current)
    current_version
    ;;
  release)
    [[ $# -eq 2 ]] || { usage; exit 1; }
    release "$2"
    ;;
  *)
    usage
    exit 1
    ;;
esac
