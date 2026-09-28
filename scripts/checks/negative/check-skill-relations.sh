#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Negative case for check-skill-relations.sh. Reciprocity holds inside a layer
# and from a public skill to a vault skill, but a vault skill may point at a
# public one without a link back: the public skill cannot name a private skill
# without publishing that name. Both directions have a twin here.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/scripts/checks" "$TMP/scripts/lib" "$TMP/system/skills/a" "$TMP/system/skills/b" "$TMP/v/skills/p"
cp "$ROOT_DIR/scripts/checks/check-skill-relations.sh" "$TMP/scripts/checks/"
cp "$ROOT_DIR/scripts/lib/vault.sh" "$TMP/scripts/lib/"
ln -s "$TMP/v" "$TMP/vault"

skill() { printf -- '---\nname: %s\nrelated: [%s]\n---\n' "$2" "$3" > "$1/SKILL.md"; }
run() { AGENTBRAIN_DIR="$TMP" VAULT_DIR="$TMP/v" bash "$TMP/scripts/checks/check-skill-relations.sh" >/dev/null 2>&1; }
fail=0
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (exit $2, want $3)" >&2; fail=1; fi; }

skill "$TMP/system/skills/a" a ""
skill "$TMP/system/skills/b" b ""
skill "$TMP/v/skills/p" p "a"
run; expect "vault skill may point at a public one without a link back" "$?" 0

skill "$TMP/system/skills/a" a "b"
run; expect "public to public still needs the link back" "$?" 1

skill "$TMP/system/skills/a" a ""
skill "$TMP/system/skills/b" b "p"
skill "$TMP/v/skills/p" p ""
run; expect "public to vault still needs the link back" "$?" 1

exit "$fail"
