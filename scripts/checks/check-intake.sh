#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-intake.sh — refuse invisible characters at the moment a note is written.
#
# The brain is read back by agents at session start. That makes text arriving
# from outside — a transcript, a pasted web page, a chat export — untrusted
# input, not just content: a character a person cannot see is one an agent
# still reads.
#
# Three families, all invisible to a reader:
#   zero-width      ZWSP/ZWNJ/ZWJ/word-joiner/BOM/soft-hyphen. Usually harmless
#                   copy-paste residue, but they also split a word so no search
#                   or NDA marker matches it.
#   bidi control    LRO/RLO/PDI and friends. These REORDER what is displayed,
#                   so the rendered line can say the opposite of the bytes.
#   unicode tags    U+E0000..U+E007F. Invisible everywhere, carry full ASCII.
#
# Zero-width residue can be stripped safely and --fix does so. Bidi and tag
# characters are never auto-fixed: removing one changes what the line means, so
# a person has to look.
#
# Where this runs:
#   moment of write   the PostToolUse hook, on the one file just written
#   commit            --staged, on the lines a commit adds
#
# A ratchet, not a sweep. The vault holds 188 of these in files imported years
# ago; gating all of them would produce a check that is always red.
#
# Usage:
#   check-intake.sh <path>...      scan files (a directory is walked)
#   check-intake.sh --staged       scan the lines the staged changes add
#   check-intake.sh --fix <path>   strip zero-width residue, report the rest
set -uo pipefail

MODE="paths"; FIX=0; PATHS=()
for a in "$@"; do
	case "$a" in
	--staged) MODE="staged" ;;
	--fix) FIX=1 ;;
	-h | --help)
		sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-*)
		echo "check-intake: unknown option: $a" >&2
		exit 2
		;;
	*) PATHS+=("$a") ;;
	esac
done

command -v python3 >/dev/null 2>&1 || exit 0 # no python: no opinion, never a false gate

SCAN=$(
	cat <<'PY'
import sys, unicodedata

ZERO_WIDTH = {0x200B:"ZERO WIDTH SPACE",0x200C:"ZERO WIDTH NON-JOINER",
              0x200D:"ZERO WIDTH JOINER",0x2060:"WORD JOINER",
              0xFEFF:"ZERO WIDTH NO-BREAK SPACE (BOM)",0x00AD:"SOFT HYPHEN"}
BIDI = {0x202A:"LEFT-TO-RIGHT EMBEDDING",0x202B:"RIGHT-TO-LEFT EMBEDDING",
        0x202C:"POP DIRECTIONAL FORMATTING",0x202D:"LEFT-TO-RIGHT OVERRIDE",
        0x202E:"RIGHT-TO-LEFT OVERRIDE",0x2066:"LEFT-TO-RIGHT ISOLATE",
        0x2067:"RIGHT-TO-LEFT ISOLATE",0x2068:"FIRST STRONG ISOLATE",
        0x2069:"POP DIRECTIONAL ISOLATE",0x061C:"ARABIC LETTER MARK",
        0x200E:"LEFT-TO-RIGHT MARK",0x200F:"RIGHT-TO-LEFT MARK"}

def classify(ch):
    o = ord(ch)
    if 0xE0000 <= o <= 0xE007F: return "tag", "UNICODE TAG (carries hidden ASCII)"
    if o in BIDI:               return "bidi", BIDI[o]
    if o in ZERO_WIDTH:         return "zero-width", ZERO_WIDTH[o]
    return None, None

def scan(text, label, out):
    for ln, line in enumerate(text.splitlines(), 1):
        for ch in line:
            kind, name = classify(ch)
            if kind:
                out.append((label, ln, kind, name, f"U+{ord(ch):04X}"))
PY
)

report_and_exit() { # <count-of-blocking>
	if [ "$1" -gt 0 ]; then
		echo "" >&2
		echo "  Zero-width residue: rerun with --fix to strip it." >&2
		echo "  Bidi and tag characters: look at the line yourself. Removing one" >&2
		echo "  changes what it says, so this refuses to guess." >&2
		exit 1
	fi
	exit 0
}

# Paths this check is allowed to skip, with their reasons and end dates, in the
# register every other check reads. Vendored bundles are the structural case: an
# invisible character there is the library's, and the rule is about characters
# smuggled into text a human wrote.
_REG="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)/lib/exemptions.tsv"
INTAKE_EXEMPT=""
[ -f "$_REG" ] && INTAKE_EXEMPT="$(awk -F'\t' '$1=="intake"{print $2}' "$_REG")"
export INTAKE_EXEMPT

if [ "$MODE" = "staged" ]; then
	git diff --cached -U0 --no-color 2>/dev/null |
		python3 -c "
$SCAN
import sys
import os, re as _re
_ex = [p for p in os.environ.get('INTAKE_EXEMPT','').split('\n') if p.strip()]
def _exempt(p):
    return any(_re.search(pat, p) for pat in _ex)
added, path = [], '?'
for raw in sys.stdin.read().splitlines():
    if raw.startswith('+++ b/'): path = raw[6:]
    elif raw.startswith('+') and not raw.startswith('+++'):
        if not _exempt(path):
            added.append((path, raw[1:]))
out = []
for p, line in added:
    scan(line, p, out)
seen = set()
for label, _ln, kind, name, cp in out:
    key = (label, kind, name)
    if key in seen: continue
    seen.add(key)
    print(f'  {label}: {name} ({cp})', file=sys.stderr)
sys.exit(1 if out else 0)
" || {
		echo "check-intake: staged changes add invisible characters." >&2
		report_and_exit 1
	}
	echo "check-intake: ok (staged)"
	exit 0
fi

[ "${#PATHS[@]}" -gt 0 ] || {
	echo "check-intake: need a path or --staged" >&2
	exit 2
}

FIX="$FIX" python3 -c "
$SCAN
import os, pathlib, sys

fix = os.environ.get('FIX') == '1'
targets = []
for arg in sys.argv[1:]:
    p = pathlib.Path(arg)
    if p.is_dir():
        targets += [f for f in p.rglob('*') if f.is_file() and f.suffix in ('.md', '.txt', '.json')]
    elif p.is_file():
        targets.append(p)

out, fixed = [], 0
for f in targets:
    try: text = f.read_text(errors='ignore')
    except OSError: continue
    found = []
    scan(text, str(f), found)
    if not found: continue
    if fix:
        cleaned = ''.join(c for c in text if classify(c)[0] != 'zero-width')
        if cleaned != text:
            f.write_text(cleaned); fixed += 1
            found = [x for x in found if x[2] != 'zero-width']
    out += found

for label, ln, kind, name, cp in out:
    print(f'  {label}:{ln}: {name} ({cp}) [{kind}]', file=sys.stderr)
if fixed:
    print(f'check-intake: stripped zero-width residue from {fixed} file(s)', file=sys.stderr)
sys.exit(1 if out else 0)
" "${PATHS[@]}" || {
	echo "check-intake: invisible characters in incoming material." >&2
	report_and_exit 1
}
echo "check-intake: ok (${#PATHS[@]} path(s))"
