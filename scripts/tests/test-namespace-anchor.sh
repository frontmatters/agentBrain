#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-namespace-anchor.sh: the vault owns the UUID5 namespace.
#
# A checkout mounted on a populated vault must hash with the vault's namespace,
# not its own, and nothing may overwrite the vault's record of it. Measured
# once: a checkout with a fresh brain.json seeded 13 notes into a shared vault
# with ids no validator accepts, and rewrote the backup on its way.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/co/scripts/setup" "$TMP/co/scripts/installer" "$TMP/vault"
ln -sfn "$TMP/vault" "$TMP/co/vault"
cp "$ROOT/scripts/setup/setup-brain-config.sh" "$TMP/co/scripts/setup/"
cp "$ROOT/scripts/installer/prompt-helper.sh" "$TMP/co/scripts/installer/" 2>/dev/null || true
VAULT_NS="11111111-1111-5111-8111-111111111111"; OWN_NS="22222222-2222-5222-8222-222222222222"
printf '%s\n' "$VAULT_NS" > "$TMP/vault/brain-namespace.backup"
printf '{"namespace": "%s", "path": "%s"}\n' "$OWN_NS" "$TMP/co" > "$TMP/co/brain.json"
VAULT="$TMP/co" bash "$TMP/co/scripts/setup/setup-brain-config.sh" >/dev/null 2>&1
got="$(python3 -c "import json;print(json.load(open('$TMP/co/brain.json'))['namespace'])")"
[ "$got" = "$VAULT_NS" ] && ok "adopt" "a checkout adopts the vault's namespace" || bad "adopt" "brain.json kept its own namespace ($got)"
[ "$(cat "$TMP/vault/brain-namespace.backup")" = "$VAULT_NS" ] && ok "write-once" "the vault's backup was not rewritten" || bad "write-once" "the backup was overwritten"
rm -f "$TMP/vault/brain-namespace.backup"
VAULT="$TMP/co" bash "$TMP/co/scripts/setup/setup-brain-config.sh" >/dev/null 2>&1
[ "$(cat "$TMP/vault/brain-namespace.backup" 2>/dev/null)" = "$VAULT_NS" ] && ok "create" "an absent backup is written from brain.json" || bad "create" "no backup written"
[ "$fail" -ne 0 ] && { echo "FAIL test-namespace-anchor" >&2; exit 1; }
echo "PASS test-namespace-anchor"
