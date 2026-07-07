#!/usr/bin/env bash
# Convenience wrapper for agentBrain setup.
# Keeps the checkout in-place; delegates to scripts/setup.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/scripts/setup.sh" "$@"
