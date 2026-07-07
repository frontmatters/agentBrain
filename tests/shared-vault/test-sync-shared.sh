#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
git init --bare -q "$SB/remote.git"
git clone -q "$SB/remote.git" "$SB/shared"
( cd "$SB/shared" && git -c user.email=a@b -c user.name=t commit --allow-empty -qm init && git push -q origin HEAD:main )
echo "# nieuwe note" > "$SB/shared/note.md"

AGENTBRAIN_SHARED_DIR="$SB/shared" AGENTBRAIN_SHARED_NO_TOKEN=1 \
  bash "$ROOT/scripts/sync-agentbrain-shared.sh" "test" \
  || { echo "FAIL: schone sync zou moeten slagen"; exit 1; }

printf 'k: sk-ant-%s\n' "0123456789abcdefghijklmno" > "$SB/shared/leak.md"
if AGENTBRAIN_SHARED_DIR="$SB/shared" AGENTBRAIN_SHARED_NO_TOKEN=1 \
   bash "$ROOT/scripts/sync-agentbrain-shared.sh" "leak"; then
  echo "FAIL: secret had push moeten blokkeren"; exit 1
fi
echo "PASS test-sync-shared"
