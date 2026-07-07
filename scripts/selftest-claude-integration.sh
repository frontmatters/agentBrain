#!/usr/bin/env bash
# DEPRECATED — superseded by scripts/selftest.sh (agent-agnostic dispatcher).
# This wrapper forwards to the new entry point, filtered to claude_code only,
# so old commands and docs keep working. Remove after the deprecation window.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf "\033[33m⚠  scripts/selftest-claude-integration.sh is deprecated → use scripts/selftest.sh\033[0m\n" >&2
exec bash "$HERE/selftest.sh" --only=claude-code "$@"
