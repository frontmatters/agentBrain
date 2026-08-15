#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT_DIR"
. scripts/platform.sh
. scripts/capability-install.sh
fails=0
assert() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got:$2 want:$3)"; fails=$((fails+1)); fi; }

# A known capability yields a non-empty recipe on this OS (macOS has brew arms).
cmd="$(capability_install_cmd ollama)"
if [ -n "$cmd" ]; then assert "ollama recipe" yes yes; else assert "ollama recipe" no yes; fi
# Unknown capability yields empty.
cmd="$(capability_install_cmd nope-cap)"
if [ -z "$cmd" ]; then assert "unknown empty" yes yes; else assert "unknown empty" no yes; fi
# offer_install on an already-present capability returns 0 without prompting.
present=""; for c in uv node clipboard; do platform_has "$c" && { present="$c"; break; }; done
if [ -n "$present" ]; then AGENTBRAIN_ASSUME_NO=1 offer_install "$present" >/dev/null 2>&1 && rc=0 || rc=$?; assert "present->0" "$rc" "0"; else echo "skip present->0 (none present)"; fi
# A missing capability with AGENTBRAIN_ASSUME_NO declines -> exit 1, no install run.
AGENTBRAIN_ASSUME_NO=1 offer_install nope-cap >/dev/null 2>&1 && rc=0 || rc=$?; assert "decline->1" "$rc" "1"

if [ "$fails" = 0 ]; then echo "test-capability-install: ok"; else echo "test-capability-install: $fails fail(s)" >&2; exit 1; fi
