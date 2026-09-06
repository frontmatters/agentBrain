#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-em-dash.sh — keep em-dashes out of prose, at the moment of writing.
#
# The rule is the maintainer's own (preferences: geen-em-dashes-in-geschreven-output),
# and its subtitle is "bij de bron, niet achteraf": replacing one afterwards
# sometimes changes what the sentence meant, while choosing the right mark while
# writing costs nothing. Until now only rendered explainers were gated, and the
# rule named commit bodies too. Measured on a single day of work: 12 of 13
# commit messages carried one, and nothing noticed.
#
# A ratchet, not a sweep. The existing tree holds roughly 3000 of these across
# 362 markdown files; gating all of them would produce a check that is always
# red, which teaches you to ignore it. So this looks only at what is NEW: the
# message being written, and the lines a commit adds.
#
# Code is exempt. CLI flags (--force), fenced blocks and backtick spans
# legitimately contain "--"; the ban is about visible prose.
#
# Usage:
#   check-em-dash.sh --message <file>   the commit message being written
#   check-em-dash.sh --staged           lines added by the staged changes
set -uo pipefail

MODE=""; TARGET=""
for a in "$@"; do
	case "$a" in
		--message) MODE="message" ;;
		--staged)  MODE="staged" ;;
		-h|--help) sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) echo "check-em-dash: unknown option: $a" >&2; exit 2 ;;
		*)  TARGET="$a" ;;
	esac
done
[ -n "$MODE" ] || { echo "check-em-dash: need --message <file> or --staged" >&2; exit 2; }

# strip_code — remove the regions where "--" is legitimate, so only prose remains.
# The program goes in -c, not on stdin: a heredoc would BE the program, and the
# data piped in would then have nowhere to arrive. Lines are blanked rather than
# deleted so grep -n keeps reporting the real line numbers.
strip_code() {
	python3 -c '
import re, sys
t = sys.stdin.read()
def blank(m): return "\n" * m.group(0).count("\n")
t = re.sub(r"```.*?```", blank, t, flags=re.S)
t = re.sub(r"`[^`\n]*`", "", t)
t = re.sub(r"^(?: {4}|\t).*$", "", t, flags=re.M)
t = re.sub(r"^\s*#.*$", "", t, flags=re.M)
sys.stdout.write(t)
'
}

BAD='—|(^|[^-])--([^-]|$)'
found=0

report() { # report <where> <line>
	printf '  %s: %s\n' "$1" "$2" >&2
	found=1
}

if [ "$MODE" = "message" ]; then
	[ -f "$TARGET" ] || { echo "check-em-dash: no such message file: $TARGET" >&2; exit 2; }
	while IFS= read -r line; do
		[ -n "$line" ] && report "commit message" "$line"
	done < <(strip_code < "$TARGET" | grep -nE "$BAD" || true)
else
	while IFS= read -r f; do
		case "$f" in *.md) ;; *) continue ;; esac
		# The existing tree keeps its debt, new prose does not add to it. Git
		# shows a modified line as one removed and one added, so an edit that
		# touches a sentence which already carried a dash is not new prose:
		# the debt grew only when the change adds more dash lines than it
		# removes. The leading '+'/'-' is stripped before the code-strip so a
		# fenced block still reads as one.
		added="$(git diff --cached -U0 -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//')"
		[ -n "$added" ] || continue
		removed="$(git diff --cached -U0 -- "$f" | grep '^-' | grep -v '^---' | sed 's/^-//')"
		n_added="$(printf '%s\n' "$added" | strip_code | grep -cE "$BAD" || true)"
		n_removed="$(printf '%s\n' "$removed" | strip_code | grep -cE "$BAD" || true)"
		[ "${n_added:-0}" -gt "${n_removed:-0}" ] || continue
		echo "  $f: $n_added dash line(s) added, $n_removed removed" >&2
		while IFS= read -r line; do
			[ -n "$line" ] && report "$f" "${line#*:}"
		done < <(printf '%s\n' "$added" | strip_code | grep -nE "$BAD" || true)
	done < <(git diff --cached --name-only --diff-filter=ACM)
fi

if [ "$found" -ne 0 ]; then
	cat >&2 <<'EOF'

check-em-dash: em-dash or "--" in prose. Use a comma, colon, semicolon,
full stop or parentheses instead. Replacing one afterwards can change what the
sentence meant, so the rule is to choose the right mark while writing.
Bypass this one commit with --no-verify when the text really needs it.
EOF
	exit 1
fi
echo "check-em-dash: ok"
