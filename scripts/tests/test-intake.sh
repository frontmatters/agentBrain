#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-intake.sh — invisible characters are caught where they arrive.
#
# The vault is read back by agents at session start, so a character a person
# cannot see is one an agent still reads. Measured before this check existed:
# 188 zero-width characters in the vault, 175 of them in one imported ChatGPT
# archive, and nothing had ever reported them.
#
# The distinction the check has to hold: zero-width residue is copy-paste
# noise and can be stripped, while a bidi override changes what a line SAYS.
# Auto-fixing the second would silently rewrite meaning, so it must refuse.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CHECK="$ROOT/scripts/checks/check-intake.sh"
fail=0
ok() { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
(d / "clean.md").write_text("# Note\n\nnothing hidden here\n")
# Written as escapes on purpose: this file must itself pass the check it tests.
(d / "zw.md").write_text("# Note\n\nhidden\u200bword\n")
(d / "bidi.md").write_text("# Note\n\n\u202ereversed line\n")
(d / "tag.md").write_text("# Note\n\ncarrier:\U000E0041\U000E0042\n")
PY

bash "$CHECK" "$TMP/clean.md" >/dev/null 2>&1 &&
	ok "clean" "a plain note passes" || bad "clean" "a clean note was reported"

bash "$CHECK" "$TMP/zw.md" >/dev/null 2>&1 &&
	bad "zero-width" "a zero-width space went unreported" ||
	ok "zero-width" "a zero-width space is reported"

out="$(bash "$CHECK" "$TMP/bidi.md" 2>&1)"
case "$out" in
*"RIGHT-TO-LEFT OVERRIDE"*) ok "bidi-named" "a bidi override is named, not just counted" ;;
*) bad "bidi-named" "a bidi override was not identified" ;;
esac

out="$(bash "$CHECK" "$TMP/tag.md" 2>&1)"
case "$out" in
*"UNICODE TAG"*) ok "tag-named" "a unicode tag character is identified" ;;
*) bad "tag-named" "a tag character went unreported" ;;
esac

# --fix strips what is safe to strip, and only that.
bash "$CHECK" --fix "$TMP/zw.md" >/dev/null 2>&1
bash "$CHECK" "$TMP/zw.md" >/dev/null 2>&1 &&
	ok "fix-strips" "--fix removes zero-width residue" ||
	bad "fix-strips" "--fix left the residue behind"

before="$(cat "$TMP/bidi.md")"
bash "$CHECK" --fix "$TMP/bidi.md" >/dev/null 2>&1
[ "$before" = "$(cat "$TMP/bidi.md")" ] &&
	ok "fix-refuses" "--fix leaves a bidi override alone" ||
	bad "fix-refuses" "--fix rewrote a line whose meaning it cannot know"

# The gates that must call it: moment of write, and the two commit boundaries.
grep -q 'check-intake' "$ROOT/scripts/claude-code-validate-note-id-hook.sh" &&
	ok "hook-wired" "the moment-of-write hook runs it" ||
	bad "hook-wired" "nothing checks a note as it is written"
grep -q 'check-intake' "$ROOT/.githooks/pre-commit" &&
	ok "precommit-wired" "the framework pre-commit runs it" ||
	bad "precommit-wired" "the framework commit boundary does not"

if [ "$fail" -eq 0 ]; then
	echo "PASS test-intake"
else
	echo "FAIL test-intake" >&2
	exit 1
fi
