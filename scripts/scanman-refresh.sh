#!/usr/bin/env bash
set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

usage() {
  echo "Usage: bash scripts/scanman-refresh.sh <repo-path> [repo-slug]" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

REPO_PATH="$(cd "$1" && pwd)"
REPO_SLUG="${2:-$(basename "$REPO_PATH" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-') }"
REPO_SLUG="${REPO_SLUG%-}"
TARGET_DIR="$AGENTBRAIN_DIR/local/research/repo-distill/$REPO_SLUG"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Scanman target missing: $TARGET_DIR" >&2
  echo "Run scanman-init first." >&2
  exit 1
fi

bash "$AGENTBRAIN_DIR/scripts/scanman-scan.sh" "$REPO_PATH" "$REPO_SLUG"
echo "Refreshed bootstrap layers while preserving enriched docs when present: $TARGET_DIR"
