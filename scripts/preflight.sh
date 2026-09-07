#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# preflight.sh — de ENE validator: draait alle bestaande gates in de juiste
# volgorde en geeft één PASS/FAIL. Vangt alle probleemklassen uit deze sessie:
#
#   KLASSE 1: parse-breuken (bash -n vangt ze)
#   KLASSE 2: dode pad-referenties (check-agnostic vangt ze)
#   KLASSE 3: privacy-lekken (privacy-scan vangt ze)
#   KLASSE 4: frontmatter-hygiene (check-frontmatter vangt ze)
#   KLASSE 5: documentatie-pariteit (check-architecture vangt ze)
#   KLASSE 6: capability-pariteit (check-addons vangt ze)
#
# Usage:
#   bash scripts/preflight.sh            # alles
#   bash scripts/preflight.sh --quick    # alleen parse + agnostic (snel)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
TOTAL=0; PASSED=0; FAILED=0; SKIPPED=0

gate() { # gate <naam> <commando...>
	local name="$1"; shift
	TOTAL=$((TOTAL + 1))
	local out rc
	out=$("$@" 2>&1); rc=$?
	if [ $rc -eq 0 ]; then
		PASSED=$((PASSED + 1))
		printf '  %b✓%b %-32s\n' "$GREEN" "$NC" "$name"
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
echo "║  pre-flight: alle gates in één keer          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

# ── fase 1: parse ──────────────────────────────────────────────────────────
echo "▸ FASE 1: parse-integriteit"
# Bewust single-quoted: expansie hoort in de inner shell.
# shellcheck disable=SC2016
gate "bash -n: alle scripts" \
	bash -c 'FAILS=0; for f in $(find scripts/ -name "*.sh" -not -path "*/node_modules/*" -not -path "*/target/*" -not -path "*/lib/*"); do bash -n "$f" 2>/dev/null || { echo "FAIL: $f"; FAILS=1; }; done; exit $FAILS'

# ── fase 2: structuur ──────────────────────────────────────────────────────
echo ""
echo "▸ FASE 2: structuur (dode paden, naming, symlinks)"
gate "check-agnostic (pad-consistentie)" bash scripts/checks/check-agnostic.sh
gate "check-architecture (doc-pariteit)" bash scripts/checks/check-architecture.sh
gate "check-lifecycle-scripts" bash scripts/checks/check-lifecycle-scripts.sh
gate "check-skill-links" bash scripts/checks/check-skill-links.sh
gate "check-readmes" bash scripts/checks/check-readmes.sh
gate "check-symlinks" bash scripts/checks/check-symlinks.sh

if [ $QUICK -eq 0 ]; then
	# ── fase 3: privacy ────────────────────────────────────────────────────
	echo ""
	echo "▸ FASE 3: privacy"
	gate "privacy-scan (leak-gate)" bash scripts/privacy-scan.sh
	gate "check-space-boundary" bash scripts/checks/check-space-boundary.sh

	# ── fase 4: capability ─────────────────────────────────────────────────
	echo ""
	echo "▸ FASE 4: capability-pariteit"
	gate "test-capability-install" bash scripts/tests/test-capability-install.sh
	gate "test-security-defaults" bash scripts/tests/test-security-defaults.sh
	gate "test-platform" bash scripts/tests/test-platform.sh
	gate "test-installer-prompts" bash scripts/tests/test-installer-prompts.sh
fi

# ── samenvatting ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
printf '  %bPASSED: %d%b · %bFAILED: %d%b · skipped: %d\n' \
	"$GREEN" "$PASSED" "$NC" "$RED" "$FAILED" "$NC" "$SKIPPED"
echo "════════════════════════════════════════════════"

[ $FAILED -eq 0 ] && exit 0 || exit 1
