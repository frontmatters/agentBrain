#!/usr/bin/env bash
# agentBrain doctor: holistic health check for public framework + private local layer when present.
# Usage:
#   bash scripts/doctor.sh                 # full local check (framework only)
#   bash scripts/doctor.sh --ci            # CI-safe: skips local-only checks
#   bash scripts/doctor.sh --summary       # compact output
#   bash scripts/doctor.sh --verbose       # full output including path lists
#   bash scripts/doctor.sh --pi-lens-strict # fail on Pi-lens review warnings too
#   bash scripts/doctor.sh --with-selftest # also run the agent-agnostic selftest
#   bash scripts/doctor.sh --all           # doctor + selftest (same as --with-selftest)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# ── Parse flags ──────────────────────────────
CI_MODE=false
VERBOSE=false
SUMMARY=false
PI_LENS_STRICT=false
WITH_SELFTEST=false
FIX=false
FAST=false

for arg in "$@"; do
	case "$arg" in
	--ci) CI_MODE=true ;;
	--verbose) VERBOSE=true ;;
	--summary) SUMMARY=true ;;
	--pi-lens-strict) PI_LENS_STRICT=true ;;
	--with-selftest|--all) WITH_SELFTEST=true ;;
	--fix) FIX=true ;;
	--fast) FAST=true ;;
	*)
		echo "Unknown flag: $arg" >&2
		exit 1
		;;
	esac
done

# ── Auto-repair (mechanical class) before diagnosing ──
if [ "$FIX" = true ] && [ -x scripts/fix.sh ]; then
	printf '\n▶ fix (auto-repair)\n'
	bash scripts/fix.sh
fi

# ── Checks ───────────────────────────────────

# Framework checks — always run
framework_checks=(
	"bash scripts/privacy-scan.sh tracked"
	"bash scripts/check-version.sh"
	"bash scripts/check-readmes.sh"
	"bash scripts/check-license.sh"
	"bash scripts/check-addons.sh"
	"bash scripts/check-architecture.sh"
	"bash scripts/check-learnings-structure.sh"
	"bash scripts/check-frontmatter.sh"
	"bash scripts/check-skill-relations.sh"
	"bash scripts/check-session-schema.sh"
	"bash scripts/check-preference-scopes.sh"
	"bash scripts/check-node-bootstrap.sh"
	"bash scripts/check-lifecycle-scripts.sh"
	"bash scripts/check-client-pointers.sh"
	"bash scripts/test-addons.sh"
	"bash scripts/check-links.sh"
	"bash scripts/check-events.sh"
	"bash scripts/check-path-naming.sh"
	"bash scripts/check-agnostic.sh"
	"bash scripts/check-anchors.sh"
	"bash scripts/check-doctor.sh"
	"bash scripts/check-launchd-templates.sh"
	"bash scripts/check-rules-pointer-sync.sh"
	"bash scripts/check-english-sources.sh"
)

# Pi-agent checks — only when Pi is installed
pi_lens_check="bash scripts/check-pi-lens.sh"
if [ "$PI_LENS_STRICT" = true ]; then
	pi_lens_check="bash scripts/check-pi-lens.sh --pi-lens-strict"
fi

pi_checks=()
if command -v pi >/dev/null 2>&1 || [ -d "$HOME/.pi/agent" ]; then
	pi_checks=(
		"$pi_lens_check"
		"bash scripts/check-pi-extension-types.sh"
		"bash scripts/test-pi-extensions.sh"
	)
else
	echo "pi not detected — skipping pi checks"
fi

public_checks=("${framework_checks[@]}" "${pi_checks[@]}")

local_checks=(
	"bash scripts/check-agentbrain-local.sh"
	"bash scripts/check-agentbrain-shared.sh"
	"bash scripts/check-brain-review.sh --local"
	"bash scripts/check-local-content.sh"
	"bash scripts/check-project-status-enum.sh"
	"bash scripts/check-spec-version.sh"
	"bash scripts/check-skill-tests.sh"
	"bash scripts/check-skill-links.sh"
	"bash scripts/check-brain-hide-forget.sh"
	"bash scripts/test-validate-note-id.sh"
	"bash scripts/test-new-note.sh"
	"bash scripts/test-loop-tick.sh"
)

# In CI mode, skip local-only checks and suppress verbose output
if [ "$CI_MODE" = true ]; then
	all_checks=("${public_checks[@]}")
else
	all_checks=("${public_checks[@]}" "${local_checks[@]}")
fi

# Fast mode: a quick pre-push gate. Keep the cheap, high-signal structural and
# privacy checks; skip the slow ones (TypeScript pi-extension checks, the test
# suites, and shellcheck below). Full validation still runs in release-check,
# deploy, and CI. Goal: the safe path is also the fast path.
if [ "$FAST" = true ]; then
	fast_checks=()
	for _c in "${all_checks[@]}"; do
		_n="$(basename "$(echo "$_c" | awk '{print $2}')" .sh)"
		case "$_n" in
		# Slow test suites + TypeScript pi-extension checks.
		check-pi-extension-types|test-pi-extensions|test-addons|test-validate-note-id|test-new-note|test-loop-tick) continue ;;
		# Vault/runtime-data scans — about knowledge content, not the framework
		# code being pushed; they belong in the full doctor, not a code pre-push.
		check-events|check-links|check-brain-review|check-local-content|check-agentbrain-local|check-agentbrain-shared|check-learnings-structure) continue ;;
		esac
		fast_checks+=("$_c")
	done
	all_checks=("${fast_checks[@]}")
fi

# ── Run ──────────────────────────────────────

if [ "$SUMMARY" = true ]; then
	printf 'agentBrain doctor (summary)\n'
	printf '============================\n'
else
	printf 'agentBrain doctor\n'
	printf '=================\n'
fi

passed=0
failed=0
failed_names=()

for check in "${all_checks[@]}"; do
	short_name="$(basename "$(echo "$check" | awk '{print $2}')" .sh)"
	if [ "$SUMMARY" = true ]; then
		printf '▶ %-30s' "$short_name"
		if output="$(eval "$check" 2>&1)"; then
			printf ' ✅\n'
			passed=$((passed + 1))
		else
			printf ' ❌\n'
			failed=$((failed + 1))
			failed_names+=("$short_name")
			echo "$output" | grep -E '(failed|Error|FATAL)' | sed 's/^/   /'
		fi
	else
		printf '\n▶ %s\n' "$check"
		if output="$(eval "$check" 2>&1)"; then
			passed=$((passed + 1))
			if [ "$VERBOSE" = false ] && [ "$short_name" = "check-path-naming" ]; then
				echo "$output" | grep -E '(passed|failed|Note:|Warning|active local|Public legacy)' || true
			else
				echo "$output"
			fi
		else
			failed=$((failed + 1))
			failed_names+=("$short_name")
			echo "$output"
		fi
	fi
done

# ── Add-on status (informational, never fails the doctor) ──
if [ "$VERBOSE" = true ] && [ -d system/addons ]; then
	echo
	echo "Add-ons (informational — run 'bash scripts/addons.sh check' for health):"
	bash scripts/addons.sh status || true
fi

# ── Bash syntax ──────────────────────────────

printf '\n▶ bash syntax'
syntax_files=()
for file in scripts/*.sh system/pi-config/setup/*.sh .githooks/pre-commit; do
	[[ -f "$file" ]] || continue
	syntax_files+=("$file")
	bash -n "$file"
done
if [ "$SUMMARY" = true ]; then
	printf ' ✅ (%d files)\n' "${#syntax_files[@]}"
else
	printf '\nBash syntax passed.\n'
fi

# ── ShellCheck ───────────────────────────────
# Slowest single step; skipped in --fast (runs in full doctor / release-check / CI).
if [ "$FAST" = true ]; then
	printf '\n▶ shellcheck (skipped in --fast)\n'
elif command -v shellcheck >/dev/null 2>&1; then
	printf '\n▶ shellcheck\n'
	# Wrap so a shellcheck failure does NOT abort the doctor before later sections
	# (selftest, summary) run. Aligns with the rest of the doctor's per-check pattern.
	if shellcheck_out="$(shellcheck scripts/*.sh system/pi-config/setup/*.sh .githooks/pre-commit 2>&1)"; then
		if [ "$SUMMARY" = true ]; then
			printf ' ✅\n'
		else
			printf 'ShellCheck passed.\n'
		fi
		passed=$((passed + 1))
	else
		if [ "$SUMMARY" = true ]; then
			printf ' ❌\n'
			printf '%s\n' "$shellcheck_out" | grep -E '^(In |\s*\^|SC[0-9]+)' | head -10 | sed 's/^/   /'
		else
			printf '%s\n' "$shellcheck_out"
			printf 'ShellCheck FAILED.\n'
		fi
		failed=$((failed + 1))
		failed_names+=("shellcheck")
	fi
else
	printf '\n▶ shellcheck\n'
	if [ "$CI_MODE" = true ]; then
		echo "ShellCheck not found in CI — this should not happen."
		exit 1
	fi
	printf 'ShellCheck not installed; skipped locally. CI installs and runs it.\n'
fi

# ── Selftest (opt-in: --with-selftest / --all) ─────────────────
# Doctor verifies framework correctness; selftest verifies per-agent integration.
# Kept separate because selftest depends on agent installs (Claude, Pi, Copilot,
# Gemini) which are user-specific and not relevant for CI framework health.

if [ "$WITH_SELFTEST" = true ]; then
	printf '\n▶ selftest (agent-agnostic integration)\n'
	if [ "$SUMMARY" = true ]; then
		if selftest_out="$(bash scripts/selftest.sh 2>&1)"; then
			# Parse the summary line: "  locale: X   passed: Y   failed: Z   warnings: W"
			summary_line="$(printf '%s\n' "$selftest_out" | grep -E 'passed:.*failed:.*warnings:' | tail -1)"
			printf '  %s\n' "${summary_line# }"
			passed=$((passed + 1))
		else
			printf '  ❌\n'
			printf '%s\n' "$selftest_out" | tail -20 | sed 's/^/   /'
			failed=$((failed + 1))
			failed_names+=("selftest")
		fi
	else
		if bash scripts/selftest.sh; then
			passed=$((passed + 1))
		else
			failed=$((failed + 1))
			failed_names+=("selftest")
		fi
	fi
fi

# ── Result ───────────────────────────────────

total=$((passed + failed))
printf '\n'
if [ "$failed" -gt 0 ]; then
	printf 'Doctor FAILED. %d/%d checks passed.\n' "$passed" "$total"
	printf 'Failed: %s\n' "${failed_names[*]}"
	exit 1
else
	printf 'Doctor passed. agentBrain is healthy. (%d checks)\n' "$total"
fi
