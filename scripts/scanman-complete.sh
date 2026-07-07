#!/usr/bin/env bash
set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

usage() {
  echo "Usage: bash scripts/scanman-complete.sh <repo-path> [repo-slug] [goal...]" >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

REPO_PATH="$(cd "$1" && pwd)"
shift || true
REPO_SLUG="${1:-$(basename "$REPO_PATH" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-') }"
REPO_SLUG="${REPO_SLUG%-}"
if [[ $# -gt 0 ]]; then shift; fi
GOAL="${*:-Complete repo distillation}"
TARGET_DIR="$AGENTBRAIN_DIR/local/research/repo-distill/$REPO_SLUG"

if [[ ! -d "$TARGET_DIR" ]]; then
  bash "$AGENTBRAIN_DIR/scripts/scanman-init.sh" "$REPO_SLUG" "$REPO_PATH" "$GOAL"
fi

bash "$AGENTBRAIN_DIR/scripts/scanman-refresh.sh" "$REPO_PATH" "$REPO_SLUG"

echo "Scanman complete-script finished bootstrap refresh for: $TARGET_DIR"
echo "Note: semantic strict-runtime/strict-distill enrichment still requires an agent pass until deeper automation exists."
