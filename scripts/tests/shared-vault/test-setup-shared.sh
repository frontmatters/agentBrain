#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export HOME="$SB"
mkdir -p "$SB/checkout"

# Bootstrap: no remote → bare repo + clone + symlink
AGENTBRAIN_ASSUME_YES=1 VAULT="$SB/checkout" \
  bash "$ROOT/scripts/setup/setup-shared-vault.sh" --bootstrap
[ -L "$SB/checkout/shared" ] || { echo "FAIL: shared/ symlink missing"; exit 1; }
[ -d "$(readlink "$SB/checkout/shared")/.git" ] || { echo "FAIL: shared clone is not a git repo"; exit 1; }
[ -d "$SB/.agentBrain/shared-remote.git" ] || { echo "FAIL: bare remote missing"; exit 1; }
# Branch must be 'main' on both sides (sync hardcodes main; bootstrap must match — not 'master')
[ "$(git -C "$SB/.agentBrain/shared-remote.git" symbolic-ref --short HEAD 2>/dev/null)" = "main" ] \
  || { echo "FAIL: bare default branch is not 'main'"; exit 1; }
[ "$(git -C "$(readlink "$SB/checkout/shared")" branch --show-current)" = "main" ] \
  || { echo "FAIL: clone is not on 'main'"; exit 1; }

# Idempotent re-run
AGENTBRAIN_ASSUME_YES=1 VAULT="$SB/checkout" bash "$ROOT/scripts/setup/setup-shared-vault.sh" --bootstrap
[ -L "$SB/checkout/shared" ] || { echo "FAIL: not idempotent"; exit 1; }
echo "PASS test-setup-shared"
