#!/usr/bin/env bash
# Smoke test for brain-extract MVP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT="$SCRIPT_DIR/brain-extract"
FIXTURE="$SCRIPT_DIR/../fixtures/minimal-vault"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
"$EXTRACT" --vault "$FIXTURE" --keep demo-project >/dev/null

[ -d .brain-package ] || { echo "FAIL: no .brain-package/"; exit 1; }
[ -f .brain-package/manifest.yml ] || { echo "FAIL: no manifest.yml"; exit 1; }
[ -f .brain-package/CHECKSUMS.txt ] || { echo "FAIL: no CHECKSUMS.txt"; exit 1; }
[ "$(find .brain-package/notes -type f | wc -l | tr -d ' ')" = "2" ] || { echo "FAIL: expected 2 notes"; exit 1; }

echo "PASS: brain-extract MVP smoke"
