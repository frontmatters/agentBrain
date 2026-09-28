#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-vault-config.sh: standalone runtime code must not
# construct the vault from a checkout root instead of using the shared resolver.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts/checks" "$TMP/system/addons/probe"
cp "$ROOT_DIR/scripts/checks/check-vault-config.sh" "$TMP/scripts/checks/"
printf 'const path = join(BRAIN_ROOT, "vault", "learnings");\n' > "$TMP/system/addons/probe/index.ts"
cd "$TMP" || exit 1
if bash scripts/checks/check-vault-config.sh >/dev/null 2>&1; then
  echo "NEGATIVE CASE FAILED: check-vault-config accepted a direct checkout/vault path" >&2
  exit 1
fi
echo "negative case holds: check-vault-config rejects direct checkout/vault paths"
