#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/local/learnings" "$SB/shared"
OLDID="$(bash "$ROOT/scripts/uuid5-gen.sh" "local/learnings/foo")"
printf -- '---\ndate: 2026-06-21\ntype: learning\ntags: [x]\nid: %s\n---\n\n# Foo\n' "$OLDID" > "$SB/local/learnings/foo.md"

AGENTBRAIN_LOCAL_DIR="$SB/local" AGENTBRAIN_SHARED_DIR="$SB/shared" \
  bash "$ROOT/scripts/promote-to-shared.sh" learnings/foo

[ -f "$SB/shared/learnings/foo.md" ] || { echo "FAIL: niet verplaatst"; exit 1; }
[ -f "$SB/local/learnings/foo.md" ] && { echo "FAIL: origineel niet weg"; exit 1; }
NEWID="$(bash "$ROOT/scripts/uuid5-gen.sh" "shared/learnings/foo")"
grep -q "id: $NEWID" "$SB/shared/learnings/foo.md" || { echo "FAIL: id niet geregenereerd"; exit 1; }
grep -q "$OLDID" "$SB/shared/.promote-id-map" && grep -q "$NEWID" "$SB/shared/.promote-id-map" \
  || { echo "FAIL: id-map ontbreekt"; exit 1; }
echo "PASS test-promote"
