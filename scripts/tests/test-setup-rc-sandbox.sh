#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-setup-rc-sandbox.sh — a sandbox setup never writes to the user's rc file.
#
# A sandbox runs setup.sh with a throwaway AGENTBRAIN_HOME but the real $HOME,
# so any rc write lands in the user's own file. The duplicate guard cannot help:
# every sandbox has a fresh tmp path.
#
# The invariant: a sandbox leaves the rc untouched; a real install persists the
# bin dir exactly once.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

BLOCK="$(sed -n '/^# The dir we just linked `brain` into/,/^echo ""$/p' "$ROOT/scripts/setup/setup.sh" | sed '$d')"
[ -n "$BLOCK" ] || { bad "present" "no PATH-persist block in setup.sh"; echo "FAIL test-setup-rc-sandbox" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '%s\n' "$BLOCK" > "$T/block.sh"
mkdir -p "$T/user/bin" "$T/sandbox/bin"
printf '# user rc\n' > "$T/user/.zshrc"
run() { HOME="$T/user" AGENTBRAIN_HOME="$1" BRAIN_BIN_DIR="$2" SHELL=/bin/zsh PATH=/usr/bin:/bin bash "$T/block.sh" >"$T/out" 2>&1; }

run "$T/sandbox" "$T/sandbox/bin"
[ "$(cat "$T/user/.zshrc")" = "# user rc" ] && ok "sandbox" "the user's rc is left as it was" || bad "sandbox" "rc was written: $(tail -1 "$T/user/.zshrc")"

run "$T/user" "$T/user/bin"
n="$(grep -cF "$T/user/bin" "$T/user/.zshrc")"
[ "$n" -eq 1 ] && ok "real" "a real install persists its bin dir" || bad "real" "expected 1 PATH line, found $n"

run "$T/user" "$T/user/bin"
n="$(grep -cF "$T/user/bin" "$T/user/.zshrc")"
[ "$n" -eq 1 ] && ok "idempotent" "a second run adds nothing" || bad "idempotent" "expected 1 PATH line, found $n"

[ "$fail" -ne 0 ] && { echo "FAIL test-setup-rc-sandbox" >&2; exit 1; }
echo "PASS test-setup-rc-sandbox"
