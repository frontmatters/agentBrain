#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-channel-picker.sh — picking a channel selects the channel you picked.
#
# Written BEFORE migrating guide() off positional REPLY, so it records the
# behaviour that must survive the change rather than the behaviour that came out
# of it. The options are built in a loop and relabelled ("stable — current"),
# while the branch below assumed a fixed order: the same shape that, elsewhere
# in this tree, skipped an editor install the user had explicitly chosen.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"

pass=0; fail=0
t_ok()  { pass=$((pass+1)); printf '  ok: %s\n' "$1"; }
t_bad() { fail=$((fail+1)); printf '  FAIL: %s\n' "$1" >&2; }

# Drive guide() with a stubbed picker and a stubbed `main set`, so what is under
# test is the mapping from a choice to a channel and nothing else.
#
# PICK is one-based, like a keypress. CURRENT decides which row gets the
# " — current" suffix, which is the moving part: the labels differ per run.
run_pick() { # run_pick <current-channel> <1-based row>
	CURRENT="$1" PICK="$2" bash -c '
		set -uo pipefail
		. "'"$ROOT_DIR"'/scripts/installer/prompt-helper.sh" 2>/dev/null || true
		cur="$CURRENT"
		dim() { :; }
		main() { [ "${1:-}" = set ] && printf "CHOSE:%s\n" "${2:-}"; }
		ab_prompt_select() {
			while :; do case "${1:-}" in --default) shift 2 ;; *) break ;; esac; done
			shift; REPLY=$(( PICK - 1 )); return 0
		}
		ab_prompt_choose() {
			local d=""; while :; do case "${1:-}" in --default) d="$2"; shift 2 ;; *) break ;; esac; done
			shift
			local -a ids=(); while [ "$#" -ge 2 ]; do ids+=("$1"); shift 2; done
			REPLY_ID="${ids[$(( PICK - 1 ))]}"; return 0
		}
		# Extracted to a real file, never sourced from a process substitution:
		# bash 3.2 reads a sourced file with seek and a pipe cannot seek, so
		# `. <(...)` defines nothing there and says nothing about it. macOS
		# ships 3.2 as /bin/bash and the release sandbox runs on it, so this
		# test passed on the workstation and reported every row as "nothing"
		# in the sandbox.
		_g="$(mktemp "${TMPDIR:-/tmp}/guide.XXXXXX")"
		sed -n "/^guide()/,/^}/p" "'"$ROOT_DIR"'/scripts/channel.sh" > "$_g"
		# shellcheck disable=SC1090
		. "$_g"; rm -f "$_g"
		guide 2>/dev/null
	' 2>/dev/null | grep -m1 "^CHOSE:" | cut -d: -f2
}

# --- row order is stable, current channel is not ----------------------------
# The loop always emits stable, prerelease, edge; only the label changes.
for pair in "1:stable" "2:prerelease" "3:edge"; do
	row="${pair%%:*}"; want="${pair##*:}"
	got="$(run_pick stable "$row")"
	[ "$got" = "$want" ] && t_ok "row $row selects $want" || t_bad "row $row selected '${got:-nothing}', expected $want"
done

# --- and the same holds when a different row carries " — current" ------------
# Relabelling must not move what a row means.
for pair in "1:stable" "3:edge"; do
	row="${pair%%:*}"; want="${pair##*:}"
	got="$(run_pick edge "$row")"
	[ "$got" = "$want" ] && t_ok "with edge current, row $row still selects $want" || t_bad "row $row selected '${got:-nothing}'"
done

if [ "$((pass + fail))" -lt 5 ]; then
	printf 'channel-picker: only %d assertion(s) ran\n' "$((pass + fail))" >&2; exit 1
fi
printf 'channel-picker: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
