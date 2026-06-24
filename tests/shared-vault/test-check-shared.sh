#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/shared"
echo "# gewone note, geen secret" > "$SB/shared/ok.md"

AGENTBRAIN_SHARED_DIR="$SB/shared" bash "$ROOT/scripts/check-agentbrain-shared.sh" \
  || { echo "FAIL: schone shared/ zou moeten slagen"; exit 1; }

printf 'token: sk-ant-%s\n' "0123456789abcdefghijklmno" > "$SB/shared/leak.md"
if AGENTBRAIN_SHARED_DIR="$SB/shared" bash "$ROOT/scripts/check-agentbrain-shared.sh"; then
  echo "FAIL: secret had geblokkeerd moeten worden"; exit 1
fi
echo "PASS test-check-shared"
