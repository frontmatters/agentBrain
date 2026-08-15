#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-symlinks.sh — tracked symlinks must be RELATIVE and resolve inside the
# repo. An absolute target (e.g. /Users/<dev>/…) works only on the machine that
# created it and ships broken to every other install.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
fail=0
while IFS= read -r f; do
	t="$(readlink "$f" 2>/dev/null || true)"
	case "$t" in
		/*) echo "FAIL: $f -> $t (absolute target — breaks on every other machine)" >&2; fail=1 ;;
		*)  [ -e "$f" ] || { echo "FAIL: $f -> $t (dangling relative target)" >&2; fail=1; } ;;
	esac
done < <(git ls-files -s | awk '$1=="120000"{print $4}')
# shellcheck disable=SC2015  # A&&B||C bewust: B is een echo die niet faalt
[ "$fail" -eq 0 ] && echo "Symlink check passed." || { echo "Symlink check failed." >&2; exit 1; }
