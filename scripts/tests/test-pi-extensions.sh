#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run lightweight unit tests for pure Pi extension helpers.

set -euo pipefail

# Tools (npm/node/bun) live in user-scoped installs — load them before probing.
# shellcheck disable=SC1091
TOOLPATHS_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib" && pwd)"
# shellcheck disable=SC1091
. "$TOOLPATHS_DIR/_toolpaths.sh"

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
EXT_DIR="$ROOT_DIR/system/pi-config/extensions"
TEST_DIR="$EXT_DIR/tests"

if [ ! -d "$TEST_DIR" ]; then
	echo "Pi extension tests skipped: no tests directory found."
	exit 0
fi

cd "$EXT_DIR"
# Release archives intentionally do not carry dev node_modules. The pure extension
# checks below can still run, but the goal integration test needs pi-ai available.
if ! node -e "require.resolve('@earendil-works/pi-ai')" >/dev/null 2>&1; then
	echo "Pi extension tests skipped: @earendil-works/pi-ai is not installed in this checkout."
	exit 0
fi
# --experimental-test-module-mocks enables mock.module(), used by
# goal.integration.test.ts to stub the pi-ai `complete` call.
npm exec --yes --package tsx -- tsx --experimental-test-module-mocks --test tests/*.test.ts
