#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "$HERE"/bin/* "$HERE"/*.sh 2>/dev/null || true
echo "✓ brain-explain installed. Try: bash $HERE/bin/brain-explain --help"
