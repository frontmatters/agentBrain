#!/usr/bin/env bash
# check-shorthand.sh — doctor drift-guard for the shorthand addon.
#
# Invariant (only when the addon is enabled): the generated targets — the glossary
# note (local/preferences/personal/shorthand.md) and the ~/.zshrc alias block — must
# match a fresh `apply` of the merged system+local sources. Catches "edited a source
# but forgot to run apply". Mirrors check-skill-links' enabled-gated style.
#
# Delegates to `shorthand check`, which does the enabled-gate + the comparison and
# exits 1 on drift. Absent addon / no bun → skip (PASS), so this is safe everywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/system/addons/shorthand/bin/shorthand"

[ -x "$BIN" ] || { echo "check-shorthand: addon not present — skip (PASS)"; exit 0; }
command -v bun >/dev/null 2>&1 || { echo "check-shorthand: bun not on PATH — skip (PASS)"; exit 0; }

exec bun "$BIN" check
