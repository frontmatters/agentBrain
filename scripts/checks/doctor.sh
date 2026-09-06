#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# agentBrain doctor: holistic health check for public framework + private local layer when present.
# Usage:
#   bash scripts/checks/doctor.sh                 # full local check (framework only)
#   bash scripts/checks/doctor.sh --ci            # CI-safe: skips local-only checks
#   bash scripts/checks/doctor.sh --summary       # compact output
#   bash scripts/checks/doctor.sh --verbose       # full output including path lists
#   bash scripts/checks/doctor.sh --pi-lens-strict # fail on Pi-lens review warnings too
#   bash scripts/checks/doctor.sh --with-selftest # also run the agent-agnostic selftest
#   bash scripts/checks/doctor.sh --all           # doctor + selftest (same as --with-selftest)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
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
# One doctor at a time. Four of the tests below plant fixtures with fixed
# names in the real vault; a second doctor running concurrently (the pre-push
# hook's, or a manual one) trips over them and fails for no reason in the
# code. Seen: "Unable to create .../__rntest-owner__/.git/index.lock".
# realpath: symlink-proof. scripts/doctor.sh is a shim into scripts/checks/,
# and through it dirname says "scripts", one level too high.
# shellcheck source=scripts/lib/lock.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/lock.sh"
# A full doctor takes several minutes; a second one that stops waiting and
# runs anyway shares the vault with the first, and their fixtures collide.
acquire_lock doctor 900 || { echo "doctor: another doctor holds the lock (waited 15 min); not running two on one vault" >&2; exit 1; }
# Tests build git fixtures. Under a hook from a linked worktree, GIT_DIR points
# at the real checkout and every fixture command would land there.
# shellcheck source=scripts/lib/git-env.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/git-env.sh"
clear_git_env
# shellcheck source=scripts/lib/repo-snapshot.sh
. "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../lib/repo-snapshot.sh"

framework_checks=(
	"bash scripts/privacy-scan.sh tracked"
	"bash scripts/checks/check-version.sh"
	"bash scripts/checks/check-readmes.sh"
	"bash scripts/checks/check-license.sh"
	"bash scripts/checks/check-addons.sh"
	"bash scripts/checks/check-deprecations.sh"
	"bash scripts/checks/check-explainers.sh"
	"bash scripts/checks/check-architecture.sh"
	"bash scripts/checks/check-learnings-structure.sh"
	"bash scripts/checks/check-frontmatter.sh"
	"bash scripts/checks/check-skill-relations.sh"
	"bash scripts/checks/check-skills-index.sh"
	"bash scripts/checks/check-ksc.sh"
	"bash scripts/checks/check-source-paths.sh"
	"bash scripts/checks/check-writing-style.sh"
	"bash scripts/checks/check-session-schema.sh"
	"bash scripts/checks/check-preference-scopes.sh"
	"bash scripts/checks/check-node-bootstrap.sh"
	"bash scripts/checks/check-lifecycle-scripts.sh"
	"bash scripts/checks/check-session-update-quiet.sh"
	"bash scripts/checks/check-client-pointers.sh"
	"bash scripts/tests/test-addons.sh"
	"bash scripts/checks/check-links.sh"
	"bash scripts/checks/check-symlinks.sh"
	"bash scripts/checks/check-events.sh"
	"bash scripts/checks/check-path-naming.sh"
	"bash scripts/checks/check-agnostic.sh"
	"bash scripts/checks/check-doctor.sh"
	"bash scripts/checks/check-launchd-templates.sh"
	"bash scripts/checks/check-rules-pointer-sync.sh"
	"bash scripts/checks/check-prompt-cache-hygiene.sh"
	"bash scripts/checks/check-english-sources.sh"
)

# Pi-agent checks — only when Pi is installed
pi_lens_check="bash scripts/checks/check-pi-lens.sh"
if [ "$PI_LENS_STRICT" = true ]; then
	pi_lens_check="bash scripts/checks/check-pi-lens.sh --pi-lens-strict"
fi

pi_checks=()
if command -v pi >/dev/null 2>&1 || [ -d "$HOME/.pi/agent" ]; then
	pi_checks=(
		"$pi_lens_check"
		"bash scripts/checks/check-pi-extension-types.sh"
		"bash scripts/tests/test-pi-extensions.sh"
	)
else
	echo "pi not detected — skipping pi checks"
fi

public_checks=("${framework_checks[@]}" "${pi_checks[@]}")

local_checks=(
	"bash scripts/checks/check-onboarding.sh"   # onboarding completeness (G2/E2)
	"bash scripts/checks/check-nda.sh --system" # owner names in the shipping layer
	"bash scripts/checks/check-tree-purity.sh"  # the public tree is framework + addons, nothing else
	"bash scripts/tests/test-onboard-choices.sh"   # onboarding fixed-choice schema (G5/G6)
	"bash scripts/tests/test-onboard-identity.sh"   # onboarding identity template (G1/R3)
	"bash scripts/tests/test-check-prerequisites.sh"   # prerequisites preflight (clean-install)
	# Validates the machine install (brain.json namespace, local/, alias, git
	# hooks) — meaningless against a bare artifact checkout, so not in CI.
	"bash scripts/checks/check-anchors.sh"
	"bash scripts/checks/check-agentbrain-local.sh"
	"bash scripts/checks/check-agentbrain-shared.sh"
	"bash scripts/checks/check-brain-review.sh --local"
	"bash scripts/checks/check-local-content.sh"
	"bash scripts/checks/check-project-status-enum.sh"
	"bash scripts/checks/check-decisions.sh"   # ADR discipline: valid Status + mandatory Alternatives
	"bash scripts/checks/check-spec-version.sh"
	"bash scripts/checks/check-skill-tests.sh"
	"bash scripts/checks/check-skill-links.sh"
	"bash scripts/checks/check-shorthand.sh"
	"bash scripts/checks/check-brain-hide-forget.sh"
	"bash scripts/tests/test-validate-note-id.sh"
	"bash scripts/tests/test-vault-alias.sh"      # vault/ and local/ hash identically
	"bash scripts/tests/test-factory-paths.sh"    # checkout paths come from factory.json
	"bash scripts/tests/test-edge-identity.sh"    # an edge build can name itself
	"bash scripts/checks/check-vault-hygiene.sh" # foreign checkouts belong beside the vault
	"bash scripts/tests/test-vault-hygiene.sh"
	"bash scripts/tests/test-intake.sh"        # invisible characters, caught at the entry
	"bash scripts/tests/test-nda-redaction.sh" # the NDA report must not print what it protects
	"bash scripts/tests/test-commit-msg-gate.sh" # the commit-msg gates must actually execute
	"bash scripts/tests/test-em-dash-ratchet.sh" # the ratchet refuses new dashes, not touched lines
	"bash scripts/tests/test-namespace-anchor.sh" # the vault owns the UUID5 namespace; setup adopts, never overwrites
	"bash scripts/tests/test-installer-version.sh" # the installer banner names the installer, never the cwd
	"bash scripts/tests/test-lineage-switch.sh"    # LAN and online sources are interchangeable; the source wins on tags
	"bash scripts/tests/test-symlink-shim.sh"    # a commit staged through a symlink is not empty
	"bash scripts/tests/test-rename-space.sh"   # a slug rename leaves no old name and no broken id
	"bash scripts/tests/test-vault-hooks.sh"     # the vault hook a fresh install gets actually gates
	"bash scripts/tests/test-lock.sh"            # two doctors never share the vault fixtures
	"bash scripts/tests/test-repo-snapshot.sh"   # a check that touches the checkout is named
	"bash scripts/tests/test-git-env.sh"         # a worktree hook's GIT_DIR never reaches a fixture
	"bash scripts/tests/test-tree-purity.sh"     # a tracked file outside the framework is refused
	"bash scripts/tests/test-vault-lib.sh"       # one vault path definition, ratchet on the old spelling
	"bash scripts/checks/check-vault-spelling.sh --count" # how many literal vault/ paths remain
	"bash scripts/tests/test-new-note.sh"
	"bash scripts/tests/test-new-note-space.sh"
	"bash scripts/tests/test-queue.sh"
	"bash scripts/tests/test-new-space.sh"
	"bash scripts/tests/test-list-space.sh"
	"bash scripts/tests/test-active-space.sh"
	"bash scripts/tests/test-context.sh"
	"bash scripts/tests/test-loop-tick.sh"
	"bash scripts/tests/test-spaces-seal.sh"
	"bash scripts/tests/test-spaces-extract.sh"
	"bash scripts/tests/test-spaces-hygiene.sh"
	"bash scripts/tests/test-sync-space.sh"
	"bash scripts/tests/test-sync-agentbrain-local-cli.sh"
	"bash scripts/tests/test-space-boundary.sh"
	"bash scripts/checks/check-space-boundary.sh"
)

# In CI mode, skip local-only checks and suppress verbose output
if [ "$CI_MODE" = true ]; then
	all_checks=("${public_checks[@]}")
	# check-explainers spans both layers: themes are public framework, rendered
	# explainers are vault content. CI validates the shippable artifact, so scope
	# it to the public themes only (same philosophy as skipping the vault checks).
	for _i in "${!all_checks[@]}"; do
		if [ "${all_checks[_i]}" = "bash scripts/checks/check-explainers.sh" ]; then
			all_checks[_i]="EXPLAINERS_DIR=/nonexistent bash scripts/checks/check-explainers.sh"
		fi
	done
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
		check-pi-extension-types|test-pi-extensions|test-addons|test-validate-note-id|test-new-note|test-queue|test-loop-tick) continue ;;
		# Vault/runtime-data scans — about knowledge content, not the framework
		# code being pushed; they belong in the full doctor, not a code pre-push.
		check-events|check-links|check-brain-review|check-local-content|check-agentbrain-local|check-agentbrain-shared|check-learnings-structure|check-explainers) continue ;;
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
	# A check must leave this checkout as it found it: no commit, no staged
	# file, no config write. `git -C ""` addresses the cwd, so one empty
	# variable in a test fixture is enough to do all three, silently.
	snap="$(repo_snapshot)"
	if output="$(eval "$check" 2>&1)"; then rc=0; else rc=1; fi
	touched=""
	if ! touched="$(repo_snapshot_diff "$snap" 2>&1)"; then
		rc=1
		output="${output}"$'\n'"${short_name}: ${touched}"
	fi
	if [ "$SUMMARY" = true ]; then
		printf '▶ %-30s' "$short_name"
		if [ "$rc" -eq 0 ]; then
			printf ' ✅\n'
			passed=$((passed + 1))
		else
			printf ' ❌\n'
			failed=$((failed + 1))
			failed_names+=("$short_name")
			echo "$output" | grep -E '(failed|Error|FATAL|touched the checkout|was:|now:)' | sed 's/^/   /'
		fi
	else
		printf '\n▶ %s\n' "$check"
		if [ "$rc" -eq 0 ]; then
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
	if [ -n "$touched" ]; then
		echo "doctor: stopping here. '$short_name' changed this checkout; later checks would run on a repository it altered." >&2
		break
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
elif command -v shellcheck >/dev/null 2>&1 \
	|| { [ -x /opt/homebrew/bin/shellcheck ] && PATH="/opt/homebrew/bin:$PATH" && export PATH; } \
	|| { [ -x /usr/local/bin/shellcheck ] && PATH="/usr/local/bin:$PATH" && export PATH; }; then
	printf '\n▶ shellcheck\n'
	# Wrap so a shellcheck failure does NOT abort the doctor before later sections
	# (selftest, summary) run. Aligns with the rest of the doctor's per-check pattern.
	# -x: follow source= directives — the sourced lib files are analyzed in
	# context instead of every `. source` degrading to a SC1091 info finding.
	# -S warning: the same set on every shellcheck version; info and style findings
	# differ between the 0.9 on CI runners and the 0.11 on a workstation.
	if shellcheck_out="$(shellcheck -x -S warning scripts/*.sh system/pi-config/setup/*.sh .githooks/* 2>&1)"; then
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

# ── Unreachable code (SC2317) ────────────────
# Its own pass, over every shell file in the repo, because the block above
# covers three globs and the bug that motivated this sat in a file outside
# them: the prose gate was appended below the last `exit` in .githooks/
# commit-msg, so it never ran for any commit message.
#
# Nothing noticed for a simple reason: a commit-msg hook that passes is silent,
# and so is one that never runs. shellcheck had the finding all along, as
# SC2317 at severity `info`, and the pass above filters it out.
#
# `--include` restricts shellcheck to the listed codes, so this cannot be
# folded into the call above without discarding every other check. Measured at
# the time of writing: 494 shell files, 0 findings, so this is a gate and not
# a ratchet.
if [ "$FAST" != true ] && command -v shellcheck >/dev/null 2>&1; then
	printf '\n▶ unreachable code\n'
	# release-check runs this doctor inside an unpacked zip, which is not a git
	# repository. There `git ls-files` fails, the list is empty, and the step
	# passed with a green tick under a "fatal:" line. A file walk is the
	# fallback, and the count is printed so an empty scan cannot look like a
	# clean one.
	sc_files="$(git ls-files 2>/dev/null | grep -E '\.sh$|^\.githooks/' || true)"
	if [ -z "$sc_files" ]; then
		sc_files="$(find . \( -name .git -o -name node_modules -o -name local \) -prune -o -type f \( -name '*.sh' -o -path './.githooks/*' \) -print 2>/dev/null | sed 's|^\./||' || true)"
	fi
	sc_count="$(printf '%s\n' "$sc_files" | grep -c . || true)"
	if [ -z "$sc_files" ]; then
		unreach_out="no shell files found"
	else
		unreach_out="$(printf '%s\n' "$sc_files" | xargs shellcheck --include=SC2317 -S info -f gcc 2>/dev/null || true)"
	fi
	if [ -z "$unreach_out" ]; then
		if [ "$SUMMARY" = true ]; then printf ' ✅ (%s files)\n' "$sc_count"; else printf 'No unreachable code (%s files).\n' "$sc_count"; fi
		passed=$((passed + 1))
	else
		if [ "$SUMMARY" = true ]; then printf ' ❌\n'; fi
		printf '%s\n' "$unreach_out" | head -20 | sed 's/^/   /'
		printf 'Unreachable code FAILED: a command after the last exit never runs.\n'
		failed=$((failed + 1))
		failed_names+=("unreachable")
	fi
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
