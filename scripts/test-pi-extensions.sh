#!/usr/bin/env bash
# Run lightweight unit tests for pure Pi extension helpers.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_DIR="$ROOT_DIR/system/pi-config/extensions"
TEST_DIR="$EXT_DIR/tests"

if [ ! -d "$TEST_DIR" ]; then
	echo "Pi extension tests skipped: no tests directory found."
	exit 0
fi

cd "$EXT_DIR"
npm exec --yes --package tsx -- tsx --test tests/*.test.ts
