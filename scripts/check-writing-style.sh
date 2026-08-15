#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-writing-style.sh — Guard the writing standard (system/writing-style.md,
# Elements of Style). Mirrors check-ksc.sh's shape: the policy doc must exist
# (FAIL), and user-facing strings are scanned for the needless-word denylist
# (WARN-only — style is judgement; silent drift of the policy is the failure).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

errors=0
warnings=0

# 1 — The policy doc itself must exist.
if [ ! -f system/writing-style.md ]; then
	echo "check-writing-style: FAIL — system/writing-style.md missing (writing policy doc)" >&2
	errors=$((errors + 1))
fi

# 2 — Needless-word denylist in user-facing strings (echo/printf/print lines of
#     the scripts a human actually reads during install & daily use). Warn-only.
#     Kept deliberately small: every entry here has caused a real fix.
denylist='simply |in order to|please note that|very easy|quick and easy'
targets=(scripts/onboard-wizard.sh scripts/setup.sh scripts/installer/install.sh scripts/brain.sh scripts/channel.sh)
hits="$(grep -nE "(echo|printf|print\(|ln_)[^#]*(${denylist})" "${targets[@]}" 2>/dev/null || true)"
if [ -n "$hits" ]; then
	count="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
	echo "check-writing-style: WARN — $count needless-word hit(s) in user-facing strings:" >&2
	printf '%s\n' "$hits" | head -5 | sed 's/^/  - /' >&2
	echo "  (system/writing-style.md rule 2 — omit needless words)" >&2
	warnings=$((warnings + 1))
fi

# 3 — The unnamed-subject regression that started this policy: an update
#     question must say WHOSE updates. Warn-only, same scripts.
vague="$(grep -nE '(echo|printf|print\(|ln_)[^#]*[Ww]ant updates\?' "${targets[@]}" 2>/dev/null || true)"
if [ -n "$vague" ]; then
	echo "check-writing-style: WARN — update question without a subject (say 'agentBrain updates'):" >&2
	printf '%s\n' "$vague" | head -3 | sed 's/^/  - /' >&2
	warnings=$((warnings + 1))
fi

if [ "$errors" -gt 0 ]; then
	echo "check-writing-style: FAILED ($errors error(s), $warnings warning(s))" >&2
	exit 1
fi
echo "check-writing-style: ok ($warnings warning(s))"
