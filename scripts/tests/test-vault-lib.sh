#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-vault-lib.sh — one definition of the vault path, and a gate on the old spelling.
set -uo pipefail
unset VAULT AGENTBRAIN_DIR AGENTBRAIN_VAULT_DIR AGENTBRAIN_LOCAL_DIR BRAIN_DIR BRAIN_ALIAS   # a fixture test owns its brain location
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT; [ -n "$TMP" ] || exit 1
mkdir -p "$TMP/scripts/lib" "$TMP/realvault"; cp "$ROOT/scripts/lib/vault.sh" "$TMP/scripts/lib/"
# vault/ present: it wins
ln -s "$TMP/realvault" "$TMP/vault"; ln -s vault "$TMP/local"
v="$(cd "$TMP" && . scripts/lib/vault.sh && printf '%s' "$VAULT_DIR")"; [ "$v" = "$TMP/vault" ] && ok "vault-link" "resolves to <checkout>/vault" || bad "vault-link" "got $v"
# no vault/ (a checkout setup has not touched): local/ still works
rm "$TMP/vault" "$TMP/local"; ln -s "$TMP/realvault" "$TMP/local"
v="$(cd "$TMP" && . scripts/lib/vault.sh && printf '%s' "$VAULT_DIR")"; [ "$v" = "$TMP/local" ] && ok "local-fallback" "falls back to <checkout>/local" || bad "local-fallback" "got $v"
# overrides, new name and the old one tests use
v="$(cd "$TMP" && AGENTBRAIN_VAULT_DIR=/x . scripts/lib/vault.sh && printf '%s' "$VAULT_DIR")"; [ "$v" = "/x" ] && ok "env-new" "AGENTBRAIN_VAULT_DIR wins" || bad "env-new" "got $v"
v="$(cd "$TMP" && AGENTBRAIN_LOCAL_DIR=/y . scripts/lib/vault.sh && printf '%s' "$VAULT_DIR")"; [ "$v" = "/y" ] && ok "env-old" "AGENTBRAIN_LOCAL_DIR still honoured" || bad "env-old" "got $v"
# ids do not move with the name
a="$(bash "$ROOT/scripts/uuid5-gen.sh" local/learnings/probe)"; b="$(bash "$ROOT/scripts/uuid5-gen.sh" vault/learnings/probe)"; [ "$a" = "$b" ] && ok "ids" "local/ and vault/ hash to the same id" || bad "ids" "ids differ"
# the ratchet
mkdir -p "$TMP/repo/scripts/checks" "$TMP/repo/scripts/lib"; cp "$ROOT/scripts/checks/check-vault-spelling.sh" "$TMP/repo/scripts/checks/"; cp "$ROOT/scripts/lib/vault.sh" "$TMP/repo/scripts/lib/"
( cd "$TMP/repo" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm seed
  printf 'x="$ROOT/local/learnings"\n' > new.sh; git add new.sh
  bash scripts/checks/check-vault-spelling.sh --staged >/dev/null 2>&1 && exit 1 || exit 0 ) && ok "ratchet-refuses" "a new literal local/ path is refused" || bad "ratchet-refuses" "a new local/ path was accepted"
( cd "$TMP/repo" && printf '# local/ in a comment\nid="$(bash scripts/uuid5-gen.sh "local/learnings/x")"\ny="$VAULT_DIR/learnings"\n' > new.sh; git add new.sh
  bash scripts/checks/check-vault-spelling.sh --staged >/dev/null 2>&1 ) && ok "ratchet-allows" "comments, uuid5 identity strings and \$VAULT_DIR pass" || bad "ratchet-allows" "an allowed form was refused"
# The vault link is a symlink, and find does not descend into a symlink start
# point without a trailing slash or -L. Measured: two callers, both silent.
bad_find="$(grep -rnE 'find "?\$\{?[A-Za-z_]+\}?/(local|vault)"?( |$)' "$ROOT/scripts" "$ROOT/system" 2>/dev/null | grep -v 'find -L' | grep -vE '/(local|vault)/' | wc -l | tr -d ' ')"
[ "$bad_find" = "0" ] && ok "find-slash" "no find on the vault link without a trailing slash" || bad "find-slash" "$bad_find find call(s) start at the vault symlink without a slash"
grep -q 'check-vault-spelling' "$ROOT/.githooks/pre-commit" && ok "pre-commit" "pre-commit runs the ratchet" || bad "pre-commit" "pre-commit does not run the ratchet"
if [ "$fail" -eq 0 ]; then echo "PASS test-vault-lib"; else echo "FAIL test-vault-lib" >&2; exit 1; fi
