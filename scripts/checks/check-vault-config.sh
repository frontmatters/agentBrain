#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Ensure standalone runtime code does not bypass the configurable vault resolver.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

# These patterns are deliberately narrow: documentation may show the default, but
# executable code must resolve the user's vault through vault.sh or vaultDir().
PATTERN='(\$HOME|\$\{HOME\}|~/)\.?/?agentBrain/vault|join\([^)]*(BRAIN_ROOT|BRAIN),[[:space:]]*"vault'
HITS="$(rg -n --glob '*.sh' --glob '*.ts' --glob '*.mjs' \
  --glob '!**/tests/**' --glob '!**/*.test.ts' \
  --glob '!scripts/checks/check-vault-config.sh' \
  "$PATTERN" "$ROOT_DIR/scripts" "$ROOT_DIR/system" 2>/dev/null \
  | grep -vE ':[0-9]+:[[:space:]]*(#|//|\*|echo[[:space:]]|printf[[:space:]])' || true)"

if [ -n "$HITS" ]; then
  echo "check-vault-config: runtime code bypasses the configurable vault resolver:" >&2
  printf '%s\n' "$HITS" >&2
  echo "Use scripts/lib/vault.sh or the shared TypeScript vault resolver." >&2
  exit 1
fi

echo "check-vault-config: ✅ no forbidden direct vault paths in runtime code"
