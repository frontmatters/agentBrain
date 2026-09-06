#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-agnostic.sh — detect agent-specific coupling in system/ and scripts/.
# Any reference to a concrete agent name outside the whitelist is a coupling smell.
# Default: exit 0 with warnings. Use --strict to exit 1 on any hit.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
cd "$ROOT_DIR"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

# Agent names to detect (word-boundary matched, case-insensitive).
# 'pi' is short and prone to false positives — --word-regexp / \b guards catch
# pip/pin/pipeline/pi-config etc. so only standalone 'pi' tokens match.
AGENTS="claude|copilot|gemini|aider|cursor|cline|windsurf|obsidian|pi"

# Whitelisted paths: legitimate agent-specific locations. Naming an agent here is
# by design, not coupling. The remaining surface (behaviour/logic code) must stay
# agent-agnostic, so a hit there is a real smell.
#   - agent-config / pi-config       per-agent docs + Pi runtime
#   - system/skills/**               skills name agents in docs (naming, not coupling)
#   - system/addons/**               opt-in tools; manifests declare per-agent support,
#                                    implementations are inherently agent-specific
#   - system/integrations/**, tools.md   describe the per-agent wiring
#   - architecture/reference docs    document the per-agent wiring map
#   - setup-*/configure-pi/selftest/install/uninstall/move/deploy/bootstrap/release
#                                    per-agent install + integration adapters
#   - lib/_strings.sh                user-facing strings that name agents
#   - system/lib/host-agent.ts       THE agent-agnostic dispatch layer — the one
#                                    place that enumerates agents on purpose so
#                                    everything else stays agnostic (calls it blind)
#   - check-*/test-*/validate-* validators  verify the per-agent wiring on purpose
#   - addons.sh                      generates the per-client capability matrix
#   - check-agnostic.sh              this file (contains the agent list)
# rg globs are relative to the search root.
WHITELIST_GLOBS=(
	"--glob=!system/agent-config/**"
	"--glob=!system/pi-config/**"
	"--glob=!system/skills/**"
	"--glob=!system/addons/**"
	"--glob=!system/integrations/**"
	"--glob=!system/tools.md"
	"--glob=!system/architecture.md"
	"--glob=!system/reference.md"
	"--glob=!system/rules.md"
	"--glob=!system/README.md"
	"--glob=!system/skills.md"
	"--glob=!system/skill-patterns.md"
	"--glob=!system/security-guidance.md"
	"--glob=!scripts/setup*.sh"
	"--glob=!scripts/configure-pi.sh"
	"--glob=!scripts/selftest*.sh"
	"--glob=!scripts/selftest/**"
	"--glob=!scripts/tools/install-agent-clis.sh"
	"--glob=!scripts/tools/install-prerequisites.sh"
	"--glob=!scripts/uninstall.sh"
	"--glob=!scripts/sync/move-agentbrain.sh"
	"--glob=!scripts/installer/bootstrap/*.sh"
	"--glob=!scripts/brain.sh"
	"--glob=!scripts/agentbrain-pointer.sh"
	"--glob=!scripts/install-lightpanda*.sh"
	"--glob=!scripts/checks/smoke-test.sh"
	"--glob=!scripts/lib/_strings.sh"
	"--glob=!system/lib/host-agent.ts"
	"--glob=!scripts/hooks/claude-code-validate-note-id-hook.sh"
	"--glob=!scripts/checks/doctor.sh"
	"--glob=!scripts/addons.sh"
	"--glob=!scripts/check-*.sh"
	"--glob=!scripts/tests/test-*.sh"
	"--glob=!scripts/validate-*.sh"
)

# grep-fallback excludes, derived from WHITELIST_GLOBS so the two engines cannot
# drift: `**` matches across directories, `*` within one. A hand-kept copy once
# let CI (no ripgrep) report 228 hints that ripgrep excluded locally.
GREP_EXCLUDES=()
for g in "${WHITELIST_GLOBS[@]}"; do
	g="${g#--glob=!}"
	g="$(printf '%s' "$g" | sed -e 's/[.]/\\./g' -e 's#\*\*#\x01#g' -e 's#\*#[^/]*#g' -e 's#\x01#.*#g')"
	GREP_EXCLUDES+=("$g")
done

hits=0

if command -v rg >/dev/null 2>&1; then
	# The same file types as the grep fallback, so both engines see one set.
	results="$(rg -n -i --word-regexp --glob '*.sh' --glob '*.md' --glob '*.json' "${WHITELIST_GLOBS[@]}" \
		-e "$AGENTS" system/ scripts/ 2>/dev/null || true)"
else
	results="$(grep -rniE --include="*.sh" --include="*.md" --include="*.json" \
		-e "\b(${AGENTS})\b" system/ scripts/ 2>/dev/null || true)"
	for pat in "${GREP_EXCLUDES[@]}"; do
		results="$(printf '%s\n' "$results" | grep -vE "^[^:]*${pat}" || true)"
	done
fi

if [ -n "$results" ]; then
	hits="$(printf '%s\n' "$results" | wc -l | tr -d ' ')"
	printf 'check-agnostic: %d agent-coupling hint(s) outside whitelist\n' "$hits"
	printf '%s\n' "$results" | sed -n '1,10p' | sed 's/^/  /'
	[ "$hits" -gt 10 ] && printf '  ... (%d more — run bash scripts/checks/check-agnostic.sh for full list)\n' "$((hits - 10))"
	if [ "$STRICT" -eq 1 ]; then
		printf 'check-agnostic: FAIL (--strict mode)\n' >&2
		exit 1
	fi
fi

printf 'check-agnostic: %d hint(s) (warning-mode — run with --strict to fail)\n' "$hits"
