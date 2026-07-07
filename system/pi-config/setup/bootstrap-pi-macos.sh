#!/usr/bin/env bash
# Backwards-compatibility redirect.
# The bootstrap has moved to scripts/bootstrap-macos.sh.
# This file is kept so existing bookmarks / docs still work.

set -euo pipefail

AGENTBRAIN_DIR="${AGENTBRAIN_DIR:-$(cd "$(dirname "$0")/../../.." && pwd)}"

echo "Note: bootstrap has moved to scripts/bootstrap-macos.sh" >&2
exec "$AGENTBRAIN_DIR/scripts/bootstrap-macos.sh" "$@"
