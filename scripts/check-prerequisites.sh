#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-prerequisites.sh — preflight presence + minimal-version check for the tools
# agentBrain and its advanced addons need. Reports ✓ present / ✗ missing / ⚠ too old,
# skips anything already present at an acceptable version, and exits non-zero only when
# a REQUIRED bootstrap prerequisite is missing.
#
# Required (gate setup): Xcode CLT (macOS), git, python3 — needed before setup can do
# anything. Recommended (report only): Homebrew, nvm, node, bun, jq, uv — several are
# installed by scripts/install-prerequisites.sh during setup, so they must not block it.
#
# OS-gated: macOS is the fully-supported path; Linux/WSL supported; others warned.
set -uo pipefail  # not -e: run every check, then summarize.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[0;90m'; NC='\033[0m'

# Detect honestly: tools installed earlier THIS run (or via an rc edit this shell
# never sourced) live in user-scoped locations — load them before checking, so we
# never claim "missing" for something that is actually installed.
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/_toolpaths.sh"

# Minimum version FLOORS (a floor, not a pin — newer is always fine). The installer
# fetches latest bun/uv/Node; these only flag something that is too old to trust.
PY_MIN="3.9"; NODE_MIN="18.0.0"; BUN_MIN="1.0.0"; UV_MIN="0.4.0"

# version_ge A B -> 0 (true) if A >= B, comparing up to three dot-separated numeric parts.
# Portable (no `sort -V`): pads missing parts with 0 and forces base-10 (leading zeros).
version_ge() {
	local IFS=.
	# shellcheck disable=SC2206  # deliberate word-split on '.' into version parts
	local a=($1) b=($2) i x y
	for i in 0 1 2; do
		x=${a[i]:-0}; y=${b[i]:-0}
		if ((10#$x > 10#$y)); then return 0; fi
		if ((10#$x < 10#$y)); then return 1; fi
	done
	return 0
}

# Allow sourcing just the helpers (for tests) without running the checks.
[ "${AGENTBRAIN_PREREQ_LIB:-}" = "1" ] && return 0

missing_required=0

# report <symbol-status ok|miss|old> <label> <detail> <hint>
report() {
	local status="$1" label="$2" detail="$3" hint="${4:-}"
	case "$status" in
		ok)   printf "  ${GREEN}✓${NC} %-13s ${DIM}%s${NC}\n" "$label" "$detail" ;;
		miss) printf "  ${RED}✗${NC} %-13s missing ${DIM}— %s${NC}\n" "$label" "$hint" ;;
		old)  printf "  ${YELLOW}⚠${NC} %-13s %s ${DIM}— %s${NC}\n" "$label" "$detail" "$hint" ;;
	esac
}

OS="$(uname)"
case "$OS" in
	Darwin) OS_LABEL="macOS (supported)" ;;
	Linux)  OS_LABEL="Linux (supported)" ;;
	*)      OS_LABEL="$OS (unsupported — proceed at your own risk)" ;;
esac
echo "Prerequisites · ${OS_LABEL}"
echo "──────────────────────────────────────────"

# ── Required (gate) ──────────────────────────────────────────
if [ "$OS" = "Darwin" ]; then
	if xcode-select -p >/dev/null 2>&1; then
		report ok "Xcode CLT" "$(xcode-select -p)"
	else
		report miss "Xcode CLT" "" "xcode-select --install  (provides git, clang, make)"
		missing_required=1
	fi
fi

if command -v git >/dev/null 2>&1; then
	report ok "git" "$(git --version 2>/dev/null | awk '{print $3}')"
else
	report miss "git" "" "xcode-select --install (macOS) / apt install git"
	missing_required=1
fi

if command -v python3 >/dev/null 2>&1; then
	pv="$(python3 -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])' 2>/dev/null || echo 0)"
	if version_ge "$pv" "$PY_MIN"; then report ok "python3" "$pv"; else report old "python3" "$pv" "need >= $PY_MIN"; missing_required=1; fi
else
	report miss "python3" "" "brew install python3 (UUID5 generation needs it)"
	missing_required=1
fi

if command -v jq >/dev/null 2>&1; then report ok "jq" "$(jq --version 2>/dev/null | sed 's/jq-//')"
else report miss "jq" "" "brew install jq (the pre-commit privacy scan needs it)"; missing_required=1; fi

# ── Recommended (report only; installed by setup or optional) ─
if [ "$OS" = "Darwin" ]; then
	if command -v brew >/dev/null 2>&1; then report ok "Homebrew" "$(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
	else report miss "Homebrew" "" "https://brew.sh (then re-run setup)"; fi
fi

if [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then report ok "nvm" "present"
else report miss "nvm" "" "installed by scripts/install-prerequisites.sh"; fi

if command -v node >/dev/null 2>&1; then
	nv="$(node -v 2>/dev/null | sed 's/^v//')"
	if version_ge "$nv" "$NODE_MIN"; then report ok "node" "$nv"; else report old "node" "$nv" "LTS >= ${NODE_MIN%%.*} (nvm install --lts)"; fi
else report miss "node" "" "scripts/install-prerequisites.sh (nvm Node LTS)"; fi

if command -v bun >/dev/null 2>&1; then
	bv="$(bun --version 2>/dev/null)"
	if version_ge "$bv" "$BUN_MIN"; then report ok "bun" "$bv"; else report old "bun" "$bv" "need >= $BUN_MIN (re-run install-prerequisites for latest)"; fi
else report miss "bun" "" "scripts/install-prerequisites.sh (MCP + addons need it)"; fi

if command -v uv >/dev/null 2>&1; then
	uvv="$(uv --version 2>/dev/null | awk '{print $2}')"
	if version_ge "$uvv" "$UV_MIN"; then report ok "uv" "$uvv"; else report old "uv" "$uvv" "need >= $UV_MIN"; fi
else report miss "uv" "" "optional — scripts/install-prerequisites.sh"; fi

echo "──────────────────────────────────────────"
if [ "$missing_required" -ne 0 ]; then
	printf '%b\n' "${RED}Missing a required prerequisite.${NC} Install the ✗/⚠ item(s) above, then re-run."
	exit 1
fi
printf '%b\n' "${GREEN}Required prerequisites present.${NC} (Recommended tools marked ✗ are installed by setup.)"
exit 0
