#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-installer-refuses-factory.sh — the installer never runs over a factory checkout.
#
# Twice on 2026-09-06 the online installer landed on ~/Developer/agentBrain, the
# proxy link to the factory's live checkout, reset it to the published snapshot,
# re-pointed its origin and pruned the shared skills. A factory checkout carries
# a factory.json beside it; the installer must see that through the link and stop.
set -uo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
fail=0; ok() { echo "  ok[$1]: $2"; }; bad() { echo "  FAIL[$1]: $2" >&2; fail=1; }

FN="$(sed -n '/^_ab_refuse_factory() {/,/^}/p' "$ROOT/scripts/installer/install.sh")"
[ -n "$FN" ] || { bad "present" "no _ab_refuse_factory in install.sh"; echo "FAIL test-installer-refuses-factory" >&2; exit 1; }
grep -q '^_ab_refuse_factory "\$DEST" || exit \$?' "$ROOT/scripts/installer/install.sh" \
	&& ok "wired" "the guard runs on DEST before anything else" \
	|| bad "wired" "the guard is defined but never called on DEST"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '%s\n' "$FN" > "$T/fn.sh"
mkdir -p "$T/factory/agentBrain" "$T/plain/agentBrain" "$T/Developer"
printf '{}\n' > "$T/factory/factory.json"
ln -s "$T/factory/agentBrain" "$T/Developer/agentBrain"

run() { bash -c ". '$T/fn.sh'; _ab_refuse_factory '$1'" 2>"$T/err"; }

run "$T/factory/agentBrain"; rc=$?
[ "$rc" -eq 3 ] && ok "direct" "refuses a checkout beside factory.json (rc=$rc)" || bad "direct" "rc=$rc, want 3"
run "$T/Developer/agentBrain"; rc=$?
[ "$rc" -eq 3 ] && ok "through-link" "refuses through the proxy link (rc=$rc)" || bad "through-link" "rc=$rc, want 3"
grep -q "brain use dev|live" "$T/err" && ok "says-how" "names the way to switch a factory checkout" || bad "says-how" "no pointer to brain use"
run "$T/plain/agentBrain"; rc=$?
[ "$rc" -eq 0 ] && ok "plain" "a checkout without factory.json installs" || bad "plain" "rc=$rc, want 0"
run "$T/absent"; rc=$?
[ "$rc" -eq 0 ] && ok "fresh" "an absent target is a fresh install" || bad "fresh" "rc=$rc, want 0"

[ "$fail" -ne 0 ] && { echo "FAIL test-installer-refuses-factory" >&2; exit 1; }
echo "PASS test-installer-refuses-factory"
