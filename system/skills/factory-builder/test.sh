#!/usr/bin/env bash
# Doctor discovers this file and runs the factory-builder regression suites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
bash "$ROOT/bin/test-factory-language-check.sh"
bash "$ROOT/bin/test-factory-lane-origin.sh"
bash "$ROOT/bin/test-factory-link.sh"
bash "$ROOT/bin/test-factory-paths.sh"
bash "$ROOT/bin/test-factory-release.sh"
bash "$ROOT/bin/test-factory-leakscan.sh"
echo '6 passed, 0 failed'
