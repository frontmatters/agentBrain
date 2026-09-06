#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-em-dash-ratchet.sh: the em-dash gate refuses new prose dashes, not touched lines.
#
# Git shows a modified line as one removed plus one added. A ratchet that reads
# only the added side calls every edited sentence "new", and a mechanical
# rename across 174 files then reports 180 dashes that were all there before.
# Measured once, on the local/ -> vault/ docs migration.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CHECK="$ROOT/scripts/checks/check-em-dash.sh"
fail=0
ok()  { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# A fixture repo. The parent's hooks export GIT_DIR into every child, so the
# variables are cleared or the fixture commits land in the real checkout.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CEILING_DIRECTORIES="$TMP"
cd "$TMP" && git init -q . && git config user.email t@t && git config user.name t
printf 'Notes live in local/ — the private layer.\nA plain line.\n' > doc.md
git add doc.md && git commit -qm init

# An edit that keeps the dash it found: not new prose.
printf 'Notes live in vault/ — the private layer.\nA plain line.\n' > doc.md
git add doc.md
if bash "$CHECK" --staged >/dev/null 2>&1; then
	ok "touched-line" "a modified line that keeps its dash passes"
else
	bad "touched-line" "a modified line with a pre-existing dash was called new"
fi

# A line that brings a dash of its own: refused.
printf 'Notes live in vault/ — the private layer.\nA plain line — with a new dash.\n' > doc.md
git add doc.md
if bash "$CHECK" --staged >/dev/null 2>&1; then
	bad "new-dash" "a newly added dash line passed"
else
	ok "new-dash" "a newly added dash line is refused"
fi

# Moving a dash from one sentence to another leaves the debt where it was.
printf 'Notes live in vault/: the private layer.\nA plain line — with a new dash.\n' > doc.md
git add doc.md
if bash "$CHECK" --staged >/dev/null 2>&1; then
	ok "net-zero" "one dash removed, one added: the debt did not grow"
else
	bad "net-zero" "a net-zero change was refused"
fi

[ "$fail" -ne 0 ] && { echo "FAIL test-em-dash-ratchet" >&2; exit 1; }
echo "PASS test-em-dash-ratchet"
