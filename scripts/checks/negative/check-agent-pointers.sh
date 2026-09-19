#!/usr/bin/env bash
# A pointer block naming a file that is not there must fail the check.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/.claude"
printf '# config\n\n- Rules: `%s/system/rules.md`\n- Gone: `%s/system/er-is-hier-niets.md`\n' "$ROOT" "$ROOT" \
  > "$SANDBOX/.claude/CLAUDE.md"
if AGENTBRAIN_HOME="$SANDBOX" bash "$ROOT/scripts/checks/check-agent-pointers.sh" >/dev/null 2>&1; then
  echo "negative/check-agent-pointers: check passed on a dead pointer (it must not)" >&2
  exit 1
fi
echo "negative/check-agent-pointers: ok (a dead pointer is rejected)"
