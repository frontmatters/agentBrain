#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-commit-msg-gate.sh — the commit-msg hook's gates must actually run.
#
# The bug this exists for: the prose gate was appended to the bottom of a
# script whose every branch already exited. A conventional subject exits 0 a
# dozen lines earlier and a non-conventional one exits 1, so the appended block
# was unreachable for every possible commit message.
#
# Nothing noticed, because a commit-msg hook that passes is SILENT, and so is
# one that never runs. The two states are indistinguishable from the outside;
# you get green either way. It surfaced only because the first commit through
# the new gate happened to carry an em-dash.
#
# So the assertion is not "the file mentions check-em-dash". A grep would have
# passed against the broken version too: the call was right there in the file.
# The hook has to be EXECUTED and observed to refuse.
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HOOK="$ROOT/.githooks/commit-msg"
fail=0
ok() { echo "  ok[$1]: $2"; }
bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
msg() { printf '%s\n' "$1" > "$TMP/msg"; printf '%s' "$TMP/msg"; }

# The hook resolves its own root with `git rev-parse`, so it must run inside
# the checkout to find scripts/checks/.
run() { (cd "$ROOT" && bash "$HOOK" "$1" >/dev/null 2>&1); }

# 1. A clean conventional subject passes. Without this the rest proves nothing:
#    a hook that refuses everything would satisfy every other assertion here.
run "$(msg 'feat(demo): a perfectly ordinary subject')" &&
	ok "clean-passes" "an ordinary conventional subject is accepted" ||
	bad "clean-passes" "the hook refuses a subject it should accept"

# 2. Conventional Commits is still enforced.
run "$(msg 'just some words')" &&
	bad "conventional" "a non-conventional subject was accepted" ||
	ok "conventional" "a non-conventional subject is refused"

# 3. The prose gate is REACHED. This is the regression under test: the subject
#    below is valid Conventional Commits, so the script's first exit path is
#    the one that used to fire and the em-dash never got looked at.
printf 'feat(demo): a valid subject\n\nbody text with an em-dash \xe2\x80\x94 right here\n' > "$TMP/msg"
run "$TMP/msg" &&
	bad "prose-gate-reached" "an em-dash in the body passed: the gate is unreachable again" ||
	ok "prose-gate-reached" "the prose gate runs on a subject that passes the format check"

# 4. And it reads the body, not only the subject line, since that is where the
#    maintainer's own rule said commit prose lives.
printf 'feat(demo): clean subject\n\nplain body, nothing to object to\n' > "$TMP/msg"
run "$TMP/msg" &&
	ok "body-clean-passes" "a clean body is accepted" ||
	bad "body-clean-passes" "a clean body was refused"

# 5. The exemptions still short-circuit before either gate.
run "$(msg 'Merge branch main into next')" &&
	ok "merge-exempt" "a merge subject is exempt" ||
	bad "merge-exempt" "the merge exemption stopped working"

if [ "$fail" -eq 0 ]; then
	echo "PASS test-commit-msg-gate"
else
	echo "FAIL test-commit-msg-gate" >&2
	exit 1
fi
