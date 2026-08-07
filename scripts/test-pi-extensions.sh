#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run lightweight unit tests for pure Pi extension helpers.

set -euo pipefail

# Tools (npm/node/bun) live in user-scoped installs — load them before probing.
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/_toolpaths.sh"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_DIR="$ROOT_DIR/system/pi-config/extensions"
TEST_DIR="$EXT_DIR/tests"

if [ ! -d "$TEST_DIR" ]; then
	echo "Pi extension tests skipped: no tests directory found."
	exit 0
fi

cd "$EXT_DIR"
npm exec --yes --package tsx -- tsx --test tests/*.test.ts
