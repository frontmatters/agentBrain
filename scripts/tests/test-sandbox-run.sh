#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-sandbox-run.sh — sandbox-run.sh reports damage to the real agent dirs.
#
# The "untouched" line used to be printed for every existing dir without
# comparing anything, so a leaked prune still read as untouched. This pins the
# before/after comparison. The "real" home is a temp dir: the test never reads
# or writes the user's own ~/.claude, ~/.copilot or ~/.pi.
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
SR="$ROOT_DIR/scripts/tools/sandbox-run.sh"
FAKE="$(mktemp -d)"; trap 'rm -rf "$FAKE"' EXIT
mkdir -p "$FAKE/.claude/skills" "$FAKE/target"
ln -s "$FAKE/target" "$FAKE/.claude/skills/keep"
ln -s "$FAKE/target" "$FAKE/.claude/skills/prune-me"

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1" >&2; }

# 1. A command that touches nothing: exit 0, reported untouched with a real count.
out="$(HOME="$FAKE" bash "$SR" true 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "clean run exits 0" || bad "clean run exits 0 (got $rc)"
case "$out" in *"untouched: ~/.claude/skills (2 entries)"*) ok "clean run says untouched" ;; *) bad "clean run says untouched: $out" ;; esac

# 2. A command that prunes a link in the real dir: reported, and the run fails
#    even though the command itself exited 0.
out="$(HOME="$FAKE" bash "$SR" /bin/rm "$FAKE/.claude/skills/prune-me" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "damage fails the run" || bad "damage fails the run (got 0)"
case "$out" in *"CHANGED during the run: ~/.claude/skills"*) ok "damage names the dir" ;; *) bad "damage names the dir: $out" ;; esac
case "$out" in *"< prune-me -> "*) ok "damage shows the pruned link" ;; *) bad "damage shows the pruned link: $out" ;; esac
case "$out" in *"untouched: ~/.claude"*) bad "damaged dir still reported untouched" ;; *) ok "damaged dir not reported untouched" ;; esac
sb="$(printf '%s\n' "$out" | sed -n 's/^sandbox kept for inspection: \([^ ]*\) .*/\1/p')"
[ -n "$sb" ] && [ -d "$sb" ] && ok "damaged run keeps its sandbox" || bad "damaged run keeps its sandbox"
case "$sb" in "${TMPDIR:-/tmp}"/ab-sandbox.*|/tmp/ab-sandbox.*) rm -rf "$sb" ;; esac

# 3. A re-pointed link is damage too, not only a missing one.
ln -s "$FAKE" "$FAKE/other"
out="$(HOME="$FAKE" bash "$SR" /bin/ln -sfn "$FAKE/other" "$FAKE/.claude/skills/keep" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "re-pointed link fails the run" || bad "re-pointed link fails the run (got 0)"
sb="$(printf '%s\n' "$out" | sed -n 's/^sandbox kept for inspection: \([^ ]*\) .*/\1/p')"
case "$sb" in "${TMPDIR:-/tmp}"/ab-sandbox.*|/tmp/ab-sandbox.*) rm -rf "$sb" ;; esac

echo "test-sandbox-run: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
