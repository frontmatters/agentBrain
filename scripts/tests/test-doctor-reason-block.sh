#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-doctor-reason-block.sh — a failing check without keywords still gets a reason.
#
# The doctor derives the reason block from the check's output with grep. A check
# that fails without any keyword (check-onboarding lists template files) left the
# first grep empty; the second grep exited 1 on empty input, pipefail failed the
# assignment and set -e ended the doctor in silence, right after the ❌ line, on
# every machine with BSD or GNU grep (2026-09-07). The maintainer machine has
# ugrep, which exits 0 there, so the doctor never died here.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

BLOCK="$(sed -n '/^[[:space:]]*reason="\$(echo "\$output"/,/^[[:space:]]*printf .   └ open/p' "$ROOT/scripts/checks/doctor.sh")"
[ -n "$BLOCK" ] || { bad "present" "reason block not found in doctor.sh"; echo "FAIL test-doctor-reason-block" >&2; exit 1; }

# The system grep, never ugrep: that is what every install runs on.
G=/usr/bin/grep; [ -x "$G" ] || G="$(command -v grep)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
run() { { printf 'set -euo pipefail\ngrep() { %s "$@"; }\ncheck="bash scripts/checks/x.sh"\n' "$G"; printf 'output=%q\n' "$1"; printf '%s\necho REACHED\n' "$BLOCK"; } > "$T/run.sh"; bash "$T/run.sh" 2>&1; }

out="$(run $'  - identity.md (still a template)\n  - workflow.md (still a template)')"; rc=$?
case "$out" in
	*REACHED*) ok "no-keyword" "the doctor survives a failure without keywords (rc=$rc)" ;;
	*) bad "no-keyword" "the doctor died on a failure without keywords: $(printf '%s' "$out" | head -2 | tr '\n' ' ')" ;;
esac
printf '%s' "$out" | $G -q 'identity.md' && ok "fallback" "the last lines of the output become the reason" || bad "fallback" "no reason shown: $out"

out="$(run $'ok[a]: fine\n  ✗ FAIL[b]: broke\nsummary')"; rc=$?
case "$out" in
	*REACHED*) ok "keyword" "a failure with keywords still works (rc=$rc)" ;;
	*) bad "keyword" "died: $out" ;;
esac
printf '%s' "$out" | $G -q 'FAIL\[b\]' && ok "reason" "the keyword line is the reason" || bad "reason" "keyword line missing: $out"

out="$(run '')"; case "$out" in *REACHED*) ok "empty" "an empty output does not kill the doctor" ;; *) bad "empty" "died on empty output" ;; esac

[ "$fail" -ne 0 ] && { echo "FAIL test-doctor-reason-block" >&2; exit 1; }
echo "PASS test-doctor-reason-block"
