#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-pointer-guard.sh — a client config that is a symlink into the agentBrain
# checkout or its vault never gets the pointer block appended.
#
# The block carries absolute home paths. Appended through such a link it lands in
# a git-tracked product file, and the privacy scan fails on the user's own
# install. Runs against a throwaway checkout and home; nothing real is touched.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
CO="$T/checkout"; H="$T/home"
mkdir -p "$CO/scripts/setup" "$CO/.github" "$CO/vault/notes" "$H/.copilot" "$T/elsewhere"
cp "$ROOT_DIR/scripts/agentbrain-pointer.sh" "$CO/scripts/"
cp "$ROOT_DIR/scripts/setup/setup-copilot-cli.sh" "$CO/scripts/setup/"
TARGET="$H/.copilot/copilot-instructions.md"
fail=0
run() { VAULT="$CO" AGENTBRAIN_HOME="$H" BRAIN_ALIAS="$H/agentBrain" bash "$CO/scripts/setup/setup-copilot-cli.sh" >/dev/null 2>&1; }
lines() { wc -l < "$1" | tr -d ' '; }
expect() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got $2, want $3)" >&2; fail=1; fi; }

printf '# Copilot Instructions\n' > "$CO/.github/copilot-instructions.md"
ln -s "$CO/.github/copilot-instructions.md" "$TARGET"
run
expect "a link into the checkout is left untouched" "$(lines "$CO/.github/copilot-instructions.md")" "1"

rm "$TARGET"; printf '# note\n' > "$CO/vault/notes/copilot.md"
ln -s "$CO/vault/notes/copilot.md" "$TARGET"
run
expect "a link into the vault is left untouched" "$(lines "$CO/vault/notes/copilot.md")" "1"

rm "$TARGET"; printf '# mine\n' > "$T/elsewhere/copilot.md"
ln -s "$T/elsewhere/copilot.md" "$TARGET"
run
expect "a link outside agentBrain still gets the pointer" "$(grep -c '^## agentBrain' "$T/elsewhere/copilot.md")" "1"

rm "$TARGET"
run
expect "a regular client config gets the pointer" "$(grep -c '^## agentBrain' "$TARGET")" "1"

exit "$fail"
