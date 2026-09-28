#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-prereq-decision.sh — the prerequisite prompt returns the action you chose.
#
# Written before migrating decide_tool off positional REPLY, so it records the
# behaviour that has to survive rather than the behaviour that comes out.
#
# Two menus live in this one function with different option counts: three when
# the tool is present (keep, update, skip) and two when it is not (install,
# skip). Both map a row number onto a word, and confusing the two is one edit
# away. The same shape elsewhere in this tree silently skipped an editor install
# the user had explicitly chosen.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
SRC="$ROOT_DIR/scripts/tools/install-prerequisites.sh"

pass=0; fail=0
t_ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
t_bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

# det=yes drives the three-option menu, det=no the two-option one.
# PICK is one-based, like a keypress. A tty is faked so the prompt is reached.
#
# AGENTBRAIN_ASSUME_YES is unset per run, never merely left alone. The first
# version read it from the ambient environment, so the same test passed on a
# workstation and failed inside the release sandbox, where setup.sh --yes
# exports it: every row came back as the unattended answer. A test that changes
# verdict with the shell it is launched from measures the shell.
decide() { # decide <yes|no> <row>
	PICK="$2" DET="$1" AGENTBRAIN_ASSUME_YES='' bash <<'EOS' 2>/dev/null
set -uo pipefail
GREEN=""; NC=""; DIM=""; YELLOW=""
ab_prompt_select() {
	while :; do case "${1:-}" in --default) shift 2 ;; *) break ;; esac; done
	shift; REPLY=$(( PICK - 1 )); return 0
}
ab_prompt_choose() {
	while :; do case "${1:-}" in --default) shift 2 ;; *) break ;; esac; done
	shift
	ids=(); while [ "$#" -ge 2 ]; do ids+=("$1"); shift 2; done
	REPLY_ID="${ids[$(( PICK - 1 ))]}"; return 0
}
eval "$(sed -n '/^decide_tool()/,/^}/p' "$SRC" | sed 's/\[ ! -t 0 \]/false/g')"
decide_tool Probe "$DET" 1.0
EOS
}

export SRC
# --- the three-option menu (tool present) ------------------------------------
for pair in "1:keep" "2:update" "3:skip"; do
	row="${pair%%:*}"; want="${pair##*:}"
	got="$(decide yes "$row" | tail -1)"
	[ "$got" = "$want" ] && t_ok "present, row $row -> $want" || t_bad "present, row $row -> '${got:-nothing}', expected $want"
done

# --- the two-option menu (tool absent) ---------------------------------------
# Different length, same function: this is the pair that can be confused.
for pair in "1:install" "2:skip"; do
	row="${pair%%:*}"; want="${pair##*:}"
	got="$(decide no "$row" | tail -1)"
	[ "$got" = "$want" ] && t_ok "absent, row $row -> $want" || t_bad "absent, row $row -> '${got:-nothing}', expected $want"
done

# --- unattended: no prompt at all -------------------------------------------
# The path the sandbox actually takes. It must answer without reaching a menu,
# and the answer differs by branch: keep what is there, install what is not.
unattended() { # unattended <yes|no>
	PICK=99 DET="$1" AGENTBRAIN_ASSUME_YES=1 bash <<'EOS' 2>/dev/null
set -uo pipefail
GREEN=""; NC=""; DIM=""; YELLOW=""
ab_prompt_select() { echo "PROMPTED" >&2; return 1; }
ab_prompt_choose() { echo "PROMPTED" >&2; return 1; }
eval "$(sed -n '/^decide_tool()/,/^}/p' "$SRC" | sed 's/\[ ! -t 0 \]/false/g')"
decide_tool Probe "$DET" 1.0
EOS
}
for pair in "yes:keep" "no:install"; do
	det="${pair%%:*}"; want="${pair##*:}"
	got="$(unattended "$det" | tail -1)"
	[ "$got" = "$want" ] && t_ok "unattended, det=$det -> $want" || t_bad "unattended, det=$det -> '${got:-nothing}', expected $want"
done

if [ "$((pass + fail))" -lt 7 ]; then
	printf 'prereq-decision: only %d assertion(s) ran\n' "$((pass + fail))" >&2; exit 1
fi
printf 'prereq-decision: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
