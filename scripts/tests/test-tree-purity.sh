#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-tree-purity.sh — a tracked file outside the framework is refused, by name.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"; CHECK="$ROOT/scripts/checks/check-tree-purity.sh"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT; [ -n "$TMP" ] || exit 1
mkdir -p "$TMP/scripts/checks" "$TMP/system"; cp "$CHECK" "$TMP/scripts/checks/"
( cd "$TMP" && git init -q . && printf '/*\n!/system/\n!/scripts/\n!/.gitignore\n!/README.md\n' > .gitignore && printf 'x\n' > system/a.md && printf 'r\n' > README.md && git add -A && git -c user.email=t@t -c user.name=t commit -qm seed )
( cd "$TMP" && bash scripts/checks/check-tree-purity.sh >/dev/null 2>&1 ) && ok "clean" "a framework-only tree passes" || bad "clean" "a clean tree was refused"
( cd "$TMP" && mkdir -p learnings && printf 'n\n' > learnings/note.md && git add -f learnings/note.md && out="$(bash scripts/checks/check-tree-purity.sh 2>&1)"; case "$out" in *"learnings"*) exit 0;; *) exit 1;; esac ) && ok "tracked" "a vault-shaped tracked directory is named" || bad "tracked" "learnings/ slipped through"
( cd "$TMP" && git rm -q --cached learnings/note.md && printf '!/spike/\n' >> .gitignore && out="$(bash scripts/checks/check-tree-purity.sh 2>&1)"; case "$out" in *"spike"*) exit 0;; *) exit 1;; esac ) && ok "allowlist" "a propped-open .gitignore door is named" || bad "allowlist" "an extra !/ line slipped through"
if [ "$fail" -eq 0 ]; then echo "PASS test-tree-purity"; else echo "FAIL test-tree-purity" >&2; exit 1; fi
