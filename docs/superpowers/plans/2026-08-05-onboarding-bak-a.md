# Onboarding Bak A — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the highest-leverage onboarding gaps ("Bak A") from the gap-matrix so a fresh agentBrain install cannot end up "installed but entirely un-configured".

**Architecture:** agentBrain onboarding has two phases — an install shell orchestrator (`scripts/setup.sh`) and an agent-driven skill (`system/skills/onboard/SKILL.md`). Bak A improvements are additive: small self-contained scripts + skill-content edits, each wired into the existing `doctor.sh` check-runner and the bash test suite. No new frameworks.

**Tech Stack:** Bash (POSIX-ish, `set -euo pipefail`), the repo's fixture-based bash test pattern (see `scripts/test-queue.sh`), Markdown skills, `scripts/doctor.sh` check-runner.

---

## Scope decomposition (why this is 5 sub-plans, not one)

Bak A spans five independent subsystems. Each sub-plan produces working, testable software on its own and can be executed/committed separately. **This document fully specifies Sub-plan 1.** Sub-plans 2–5 are scoped here as a roadmap and get their own concrete plans when picked up.

| # | Sub-plan | Gaps | Touches |
|---|----------|------|---------|
| **1** | **Onboarding completeness check + surfacing** (this doc) | G2 (core), E2 | `scripts/check-onboarding.sh` (new), `scripts/doctor.sh`, `scripts/setup.sh` |
| 2 | Fixed-choice intake + locale unification | G5, G6 | `system/skills/onboard/SKILL.md`, `scripts/lib/_strings.sh` |
| 3 | Identity step + template | G1, R3 | `user-preferences/identity.md` (new), `scripts/setup-templates.sh`, `SKILL.md` |
| 4 | MCP provisioning | G15 | `system/addons/agentbrain-mcp/` install path |
| 5 | Real agent id on the event bus | E6 | event-bus tooling (`FROM_AGENT`/`BRAIN_AGENT`) |

**Follow-on (not in Sub-plan 1):** the agent-session-start *nag* half of G2 (a pointer/hook that auto-surfaces incompleteness at session start) builds on the check from Sub-plan 1 and is a separate, agent-specific increment.

---

## Sub-plan 1 — Onboarding completeness check + surfacing

**What it delivers:** a single source of truth for "is this brain onboarded yet?" — detected from real state (placeholder markers in personal preferences), wired into `doctor` (so drift is visible) and printed by `setup.sh` at the end of install (so a fresh install says "not personalized yet" instead of a easy-to-ignore hint). This is the core of the G2 seam and the E2 completeness signal.

**Design note:** completeness is *detected from state*, not tracked by a separate marker file — consistent with the skill's "detect before ask" contract. The canonical "not onboarded" test is the placeholder markers `This is an example` and `^<!-- Example:` (the exact set `config/SKILL.md` and `/onboard` already use).

### File structure

- **Create** `scripts/check-onboarding.sh` — reports completeness; exit 0 = complete, exit 1 = incomplete. One responsibility.
- **Create** `scripts/test-check-onboarding.sh` — fixture-based unit tests.
- **Modify** `scripts/doctor.sh` — add the check to the `local_checks` array (vault-layer check).
- **Modify** `scripts/setup.sh` — surface completeness at the end of install.

---

### Task 1: Onboarding completeness check script

**Files:**
- Create: `scripts/check-onboarding.sh`
- Test: `scripts/test-check-onboarding.sh`

- [ ] **Step 1: Write the failing test**

Create `scripts/test-check-onboarding.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-check-onboarding.sh — unit tests for scripts/check-onboarding.sh.
# shellcheck disable=SC2015  # `assert && pass || fail` is the intended test-assert idiom here
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/test-onboarding-XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts" "$FIXTURE/local/preferences/personal"
cp "$ROOT_DIR/scripts/check-onboarding.sh" "$FIXTURE/scripts/"
PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

PREFS="$FIXTURE/local/preferences/personal"

# 1) A template placeholder → incomplete (exit != 0)
printf -- '---\n---\nThis is an example preference.\n' > "$PREFS/communication.md"
if (cd "$FIXTURE" && bash scripts/check-onboarding.sh >/dev/null 2>&1); then
  fail "placeholder should report incomplete"; else pass "placeholder → incomplete"; fi

# 2) A README is ignored, not counted as a placeholder
printf -- 'This is an example README.\n' > "$PREFS/README.md"
printf -- '---\n---\nIk wil Nederlands, beknopt.\n' > "$PREFS/communication.md"
if (cd "$FIXTURE" && bash scripts/check-onboarding.sh >/dev/null 2>&1); then
  pass "README ignored, personalized → complete"; else fail "README should be ignored"; fi

# 3) Missing personal dir → incomplete
rm -rf "$PREFS"
if (cd "$FIXTURE" && bash scripts/check-onboarding.sh >/dev/null 2>&1); then
  fail "missing dir should be incomplete"; else pass "missing dir → incomplete"; fi

echo "  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/test-check-onboarding.sh`
Expected: FAIL — `cp: .../scripts/check-onboarding.sh: No such file or directory` (the script does not exist yet).

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/check-onboarding.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check-onboarding.sh — report whether personal onboarding is complete.
# "Complete" = no personal preference file still carries a template placeholder
# marker (the same markers /config preferences and /onboard treat as "needs
# onboarding"). Exit 0 = complete, exit 1 = incomplete — so doctor and setup can
# surface the drift (gap G2 seam / E2 completeness signal).
set -euo pipefail
VAULT="${VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
PREFS="$VAULT/local/preferences/personal"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Canonical "not onboarded yet" markers (see system/skills/config/SKILL.md).
markers='This is an example|^<!-- Example:'

incomplete=()
if [ -d "$PREFS" ]; then
  while IFS= read -r f; do
    base="$(basename "$f")"
    [ "$base" = "README.md" ] && continue
    if grep -qE "$markers" "$f"; then incomplete+=("$base"); fi
  done < <(find "$PREFS" -maxdepth 1 -name '*.md' -type f | sort)
fi

if [ ! -d "$PREFS" ] || [ "${#incomplete[@]}" -gt 0 ]; then
  echo -e "${YELLOW}Onboarding incomplete${NC} — run /onboard to personalize:"
  if [ ! -d "$PREFS" ]; then
    echo "  local/preferences/personal/ missing"
  else
    for b in "${incomplete[@]}"; do echo "  - $b (still a template)"; done
  fi
  exit 1
fi
echo -e "${GREEN}Onboarding complete${NC} — personal preferences personalized."
exit 0
```

Then make it executable:

```bash
chmod +x scripts/check-onboarding.sh
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/test-check-onboarding.sh`
Expected: PASS — three `✓` lines and `passed: 3  failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/check-onboarding.sh scripts/test-check-onboarding.sh
git commit -m "feat(onboard): add onboarding-completeness check (G2/E2)"
```

---

### Task 2: Wire the check into `doctor`

**Files:**
- Modify: `scripts/doctor.sh` (the `local_checks=(` array, starts at line 100)

- [ ] **Step 1: Write the failing test**

Append to `scripts/test-check-onboarding.sh`, just before the final `echo "  passed: ..."` line:

```bash
# 4) doctor wires the check into its vault-layer checks
if grep -q 'check-onboarding.sh' "$ROOT_DIR/scripts/doctor.sh"; then
  pass "doctor runs check-onboarding"; else fail "doctor does not run check-onboarding"; fi
```

- [ ] **Step 2: Run the test to verify the new assertion fails**

Run: `bash scripts/test-check-onboarding.sh`
Expected: the new line prints `✗ doctor does not run check-onboarding` and the run exits non-zero (`failed: 1`).

- [ ] **Step 3: Add the check to `local_checks`**

In `scripts/doctor.sh`, find the `local_checks=(` array (line 100). Add this entry as the first line inside the array (right after `local_checks=(`):

```bash
	"bash scripts/check-onboarding.sh"   # onboarding completeness (G2/E2)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/test-check-onboarding.sh`
Expected: PASS — now `passed: 4  failed: 0`.

- [ ] **Step 5: Sanity-run the doctor**

Run: `bash scripts/doctor.sh --summary`
Expected: a `▶ check-onboarding` line appears in the output (✅ or ❌ depending on this vault's real onboarding state — both are valid; the point is the check now runs).

- [ ] **Step 6: Commit**

```bash
git add scripts/doctor.sh scripts/test-check-onboarding.sh
git commit -m "feat(doctor): surface onboarding completeness as a vault check (E2)"
```

---

### Task 3: Surface completeness at the end of install

**Files:**
- Modify: `scripts/setup.sh` (the "Next steps" block near lines 336–346)

- [ ] **Step 1: Add the surfacing block**

In `scripts/setup.sh`, immediately AFTER the existing `echo "Next:"` block (the lines printing `/onboard`, `brain status`, `bash scripts/doctor.sh`), and BEFORE the Obsidian `if` block, insert:

```bash
# Surface onboarding completeness (gap G2 seam / E2): make "installed but not
# personalized" visible, instead of a hint that is easy to ignore.
if ! bash "${SCRIPTS}/check-onboarding.sh" >/dev/null 2>&1; then
	echo ""
	echo -e "${YELLOW}⚠ Installed, but your brain is not personalized yet.${NC}"
	echo "  Run /onboard inside your agent — or 'bash scripts/check-onboarding.sh' to see what's missing."
fi
```

- [ ] **Step 2: Verify it runs without breaking setup**

Run: `bash -n scripts/setup.sh`
Expected: no output (syntax OK).

- [ ] **Step 3: Manually verify the message logic**

Run: `bash scripts/check-onboarding.sh; echo "exit=$?"`
Expected: prints either "Onboarding complete" (exit=0) or "Onboarding incomplete" (exit=1) for this vault — confirming the same call setup.sh now makes.

- [ ] **Step 4: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat(setup): print onboarding-incomplete warning at end of install (G2)"
```

---

## Self-Review (Sub-plan 1)

- **Spec coverage:** G2-core (seam is now surfaced at install end + doctor) → Tasks 2 & 3. E2 (drift/completeness signal detectable) → Task 1 & 2. The G2 *session-start nag* is explicitly deferred to a follow-on (documented above), not silently dropped.
- **Placeholder scan:** no TBD/TODO; every code step shows complete code and exact run/expected lines.
- **Type/name consistency:** the script `scripts/check-onboarding.sh`, the marker string `This is an example|^<!-- Example:`, and the `local_checks` array reference are used identically across Tasks 1–3.
- **Assumption to verify at execution:** `scripts/setup.sh` defines `YELLOW` and `SCRIPTS` in scope at the insertion point — both are declared earlier in setup.sh (YELLOW ~line 74, SCRIPTS ~line 28). If a future refactor moves them, adjust the insert accordingly.

---

## Roadmap — Sub-plans 2–5 (to be planned concretely when picked up)

2. **Fixed-choice intake + locale unification (G5, G6):** rewrite the `SKILL.md` Step-1 questions from prose into enumerated fixed choices (channel, update-mode, verbosity, autonomy, scope, design dark/light/both); unify the Step-1 language question with the Step-5 UI-locale so locale is *derived*, and emit an explicit "not supported — run /add-locale?" signal for codes outside `scripts/lib/_strings.sh`.
3. **Identity step + template (G1, R3):** add `user-preferences/identity.md`, seed it via `scripts/setup-templates.sh`, add an `/onboard identity` step that reads+confirms `git config user.name/user.email` and supports a per-project-type/per-space identity routing table.
4. **MCP provisioning (G15):** when `agentbrain-mcp` is enabled, actually register the MCP server into each detected agent's config (not just write pointers); fail loudly if enabled-but-unregistered.
5. **Real agent id on the event bus (E6):** set the agent identity during onboarding and stop defaulting event-bus `FROM_AGENT`/`BRAIN_AGENT` to `claude`.
