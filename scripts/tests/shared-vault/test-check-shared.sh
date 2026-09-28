#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/shared"
echo "# ordinary note, no secret" > "$SB/shared/ok.md"

AGENTBRAIN_SHARED_DIR="$SB/shared" bash "$ROOT/scripts/checks/check-agentbrain-shared.sh" \
  || { echo "FAIL: a clean shared/ should pass"; exit 1; }

printf 'token: sk-ant-%s\n' "0123456789abcdefghijklmno" > "$SB/shared/leak.md"
if AGENTBRAIN_SHARED_DIR="$SB/shared" bash "$ROOT/scripts/checks/check-agentbrain-shared.sh"; then
  echo "FAIL: the secret should have been blocked"; exit 1
fi
echo "PASS test-check-shared"
