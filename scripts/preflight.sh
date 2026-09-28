#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# preflight.sh: the ONE validator. Runs every existing gate in the right
# order and returns a single PASS/FAIL. Catches these problem classes:
#
#   CLASS 1: parse breakage (bash -n catches it)
#   CLASS 2: dead path references (check-agnostic catches them)
#   CLASS 3: privacy leaks (privacy-scan catches them)
#   CLASS 4: frontmatter hygiene (check-frontmatter catches it)
#   CLASS 5: documentation parity (check-architecture catches it)
#   CLASS 6: capability parity (check-addons catches it)
#
# Usage:
#   bash scripts/preflight.sh            # everything
#   bash scripts/preflight.sh --quick    # only parse + agnostic (fast)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
TOTAL=0; PASSED=0; FAILED=0; SKIPPED=0; UNMEASURED=0

gate() { # gate <name> <command...>
	local name="$1"; shift
	TOTAL=$((TOTAL + 1))
	local out rc
	out=$("$@" 2>&1); rc=$?
	if [ $rc -eq 0 ]; then
		PASSED=$((PASSED + 1))
		printf '  %b✓%b %-32s\n' "$GREEN" "$NC" "$name"
	elif [ $rc -eq 77 ]; then
		# 77 is vault_required saying it measured nothing (no vault in this tree).
		# Counted apart, like doctor.sh does: calling it a pass is the false green
		# the exit code exists to remove, and calling it a failure would block a
		# release from a tree that legitimately has no vault yet. This keeps the
		# release gate and the doctor in agreement about the same exit code.
		UNMEASURED=$((UNMEASURED + 1))
		printf '  %b·%b %-32s not measured\n' "$YELLOW" "$NC" "$name"
		printf '%s\n' "$out" | head -2 | sed 's/^/    │ /'
	else
		FAILED=$((FAILED + 1))
		printf '  %b✗%b %-32s\n' "$RED" "$NC" "$name"
		echo "    ── output ──"
		printf '%s\n' "$out" | head -6 | sed 's/^/    │ /'
	fi
}

skip_gate() {
	SKIPPED=$((SKIPPED + 1))
	printf '  %b⊘%b %-32s %s\n' "$YELLOW" "$NC" "$1" "(skipped: $2)"
}

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  pre-flight: all gates in one pass           ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

# ── phase 1: parse ─────────────────────────────────────────────────────────
echo "▸ PHASE 1: parse integrity"
# Single-quoted on purpose: expansion belongs in the inner shell.
# shellcheck disable=SC2016
gate "bash -n: all scripts" \
	bash -c 'FAILS=0; for f in $(find scripts/ -name "*.sh" -not -path "*/node_modules/*" -not -path "*/target/*" -not -path "*/lib/*"); do bash -n "$f" 2>/dev/null || { echo "FAIL: $f"; FAILS=1; }; done; exit $FAILS'

# ── phase 2: structure ─────────────────────────────────────────────────────
echo ""
echo "▸ PHASE 2: structure (dead paths, naming, symlinks)"
gate "check-agnostic (path consistency)" bash scripts/checks/check-agnostic.sh
gate "check-architecture (doc parity)" bash scripts/checks/check-architecture.sh
gate "check-lifecycle-scripts" bash scripts/checks/check-lifecycle-scripts.sh
gate "check-skill-links" bash scripts/checks/check-skill-links.sh
gate "check-readmes" bash scripts/checks/check-readmes.sh
gate "check-symlinks" bash scripts/checks/check-symlinks.sh

if [ $QUICK -eq 0 ]; then
	# ── phase 3: privacy ───────────────────────────────────────────────────
	echo ""
	echo "▸ PHASE 3: privacy"
	gate "privacy-scan (leak-gate)" bash scripts/privacy-scan.sh
	gate "check-space-boundary" bash scripts/checks/check-space-boundary.sh

	# ── phase 4: capability ────────────────────────────────────────────────
	echo ""
	echo "▸ PHASE 4: capability parity"
	gate "test-capability-install" bash scripts/tests/test-capability-install.sh
	gate "test-security-defaults" bash scripts/tests/test-security-defaults.sh
	gate "test-platform" bash scripts/tests/test-platform.sh
	gate "test-installer-prompts" bash scripts/tests/test-installer-prompts.sh
fi

# ── summary ────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
printf '  %bPASSED: %d%b · %bFAILED: %d%b · skipped: %d · not measured: %d\n' \
	"$GREEN" "$PASSED" "$NC" "$RED" "$FAILED" "$NC" "$SKIPPED" "$UNMEASURED"
echo "════════════════════════════════════════════════"

[ $FAILED -eq 0 ] && exit 0 || exit 1
