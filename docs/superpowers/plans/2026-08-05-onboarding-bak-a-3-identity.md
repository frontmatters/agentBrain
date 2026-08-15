# Onboarding Bak A · Sub-plan 3 — Identity step + template

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `/onboard` an identity step that captures name, email(s), and git identity/identities — seeded from a template and detected from `git config` — so a brain records who authors its work (G1), with optional per-project-type identity routing (R3).

**Architecture:** Add one seed template `user-preferences/identity.md` (auto-picked-up by `setup-templates.sh`'s existing `user-preferences/*.md` glob and rendered into `local/preferences/personal/identity.md`), and an `identity.md` step in `SKILL.md` Step 1 that reads+confirms `git config user.name/user.email`. Identity lives in the existing personal-preferences store — **no new stack.json** (per the architecture review). A bash test validates the template + skill wiring and is added to `doctor`.

**Tech Stack:** Markdown template (with `{{uuid5}}` placeholder), the repo's fixture-based bash test pattern, `scripts/doctor.sh` check-runner, `system/skills/onboard/SKILL.md`.

**Design decisions:**
- Identity is **free-text** (name/email/git are open values), so it is NOT added to `choices.json`.
- The template carries the canonical `This is an example` marker, so the Sub-plan 1 `check-onboarding` completeness check automatically treats an un-personalized `identity.md` as "not onboarded yet" — no change needed there.
- Git/mail identities that already live in `local/integrations/` should be kept consistent, not duplicated (noted in the skill copy).

---

## File structure

- **Create** `user-preferences/identity.md` — seed template for the identity preference.
- **Create** `scripts/test-onboard-identity.sh` — validates the template + skill wiring.
- **Modify** `scripts/doctor.sh` — add the test to `local_checks`.
- **Modify** `system/skills/onboard/SKILL.md` — add the identity step + argument-hint.

---

### Task 1: identity.md template + validation test

**Files:**
- Create: `user-preferences/identity.md`
- Create: `scripts/test-onboard-identity.sh`

- [ ] **Step 1: Write the failing test**

Create `scripts/test-onboard-identity.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-onboard-identity.sh — validate the identity seed template + its /onboard wiring.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT_DIR/user-preferences/identity.md"
SETUP="$ROOT_DIR/scripts/setup-templates.sh"
PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

# 1) template exists and opens with YAML frontmatter
if [ -f "$TPL" ] && [ "$(head -n1 "$TPL")" = "---" ]; then pass "identity.md exists with frontmatter"; else fail "identity.md missing/no frontmatter"; fi
# 2) correct type + uuid5 placeholder (so setup-templates renders it)
if grep -q '^type: user-preference' "$TPL" && grep -q '^id: {{uuid5}}' "$TPL"; then pass "type + {{uuid5}} placeholder present"; else fail "type/{{uuid5}} missing"; fi
# 3) carries the canonical "not onboarded yet" marker (so check-onboarding detects it)
if grep -q 'This is an example' "$TPL"; then pass "carries onboarding marker"; else fail "no 'This is an example' marker"; fi
# 4) has the identity sections
if grep -qi '^## Name' "$TPL" && grep -qi '^## Email' "$TPL" && grep -qi '^## Git' "$TPL"; then pass "has Name/Email/Git sections"; else fail "missing identity sections"; fi
# 5) setup-templates.sh auto-seeds it via the user-preferences glob
if grep -q 'user-preferences"/\*.md' "$SETUP"; then pass "setup-templates globs user-preferences (auto-seed)"; else fail "no user-preferences glob in setup-templates"; fi

echo "  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/test-onboard-identity.sh`
Expected: FAIL — `✗ identity.md missing/no frontmatter` (template does not exist yet), non-zero exit.

- [ ] **Step 3: Create the template**

Create `user-preferences/identity.md`:

```markdown
---
date: 2026-08-05
type: user-preference
tags: [preferences, identity, git, author]
id: {{uuid5}}
---

# Identity

> **Note:** This is an example file. Customize it to reflect your own identity.

## Name
- Your name (how you want to be referred to and credited)

## Email(s)
- Primary email
- Any additional addresses (work, personal, brand)

## Git identities
- Default git author name + email used for commits
- On this machine: `git config user.name` / `git config user.email`

## Identity routing (optional)
- If you publish under more than one brand/name, which identity for which project type
  (e.g. dev/infra projects -> Brand A <a@example.dev>; consumer apps -> Brand B)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/test-onboard-identity.sh`
Expected: PASS — `passed: 5  failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add user-preferences/identity.md scripts/test-onboard-identity.sh
git commit -m "feat(onboard): add identity seed template + validation (G1/R3)"
```

---

### Task 2: Wire the identity test into `doctor`

**Files:**
- Modify: `scripts/doctor.sh` (the `local_checks=(` array, line 100)

- [ ] **Step 1: Write the failing assertion**

Append to `scripts/test-onboard-identity.sh`, before the final `echo "  passed: ..."` line:

```bash
# 6) doctor runs the identity test
if grep -q 'test-onboard-identity.sh' "$ROOT_DIR/scripts/doctor.sh"; then
  pass "doctor runs onboard-identity test"; else fail "doctor does not run onboard-identity test"; fi
```

- [ ] **Step 2: Run to verify the new assertion fails**

Run: `bash scripts/test-onboard-identity.sh`
Expected: prints `✗ doctor does not run onboard-identity test`, exits non-zero.

- [ ] **Step 3: Add to `local_checks`**

In `scripts/doctor.sh`, inside the `local_checks=(` array (line 100), add this line right after the existing `test-onboard-choices.sh` entry:

```bash
	"bash scripts/test-onboard-identity.sh"   # onboarding identity template (G1/R3)
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test-onboard-identity.sh`
Expected: PASS — `passed: 6  failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/doctor.sh scripts/test-onboard-identity.sh
git commit -m "feat(doctor): validate onboarding identity template (G1)"
```

---

### Task 3: Add the identity step to SKILL.md

**Files:**
- Modify: `system/skills/onboard/SKILL.md`

- [ ] **Step 1: Add "identity" to the argument-hint**

In `system/skills/onboard/SKILL.md`, replace this exact line (line 4):

```markdown
argument-hint: Optional focus area (e.g. "tech-stack", "communication", "organization", "team", "addons", "locale", "channel", or "spaces")
```

with:

```markdown
argument-hint: Optional focus area (e.g. "tech-stack", "communication", "identity", "organization", "team", "addons", "locale", "channel", or "spaces")
```

- [ ] **Step 2: Add the identity step to the Step 1 question list**

In `system/skills/onboard/SKILL.md`, replace this exact block (the current item 5):

```markdown
5. `decision-making.md`
   - **(choice · decision)** "How do you approach technical decisions?" — pragmatic / thorough / move fast.
   - "Build vs buy — do you prefer libraries or custom code?"
   - "How important is backwards compatibility vs. clean breaks?"
```

with:

```markdown
5. `decision-making.md`
   - **(choice · decision)** "How do you approach technical decisions?" — pragmatic / thorough / move fast.
   - "Build vs buy — do you prefer libraries or custom code?"
   - "How important is backwards compatibility vs. clean breaks?"
6. `identity.md`
   - Read `git config user.name` and `git config user.email`, show them, and ask "Attribute your commits as this? (Enter = yes)". Confirm, or capture a correction.
   - "Any additional email addresses or git identities?" (optional, free text)
   - **(optional · multi-identity)** "Do you publish under more than one brand/name? If so, which identity for which project type?" — capture a per-project-type routing table.
   - Write the name, email(s), and git identities to `identity.md`. If `local/integrations/` already records git/mail identities, keep them consistent rather than duplicating.
```

- [ ] **Step 3: Add structural assertions to the test**

Append to `scripts/test-onboard-identity.sh`, before the final `echo "  passed: ..."` line:

```bash
# 7) SKILL.md wires the identity step + argument-hint
SKILL="$ROOT_DIR/system/skills/onboard/SKILL.md"
if grep -q '6. `identity.md`' "$SKILL"; then pass "SKILL.md has the identity step"; else fail "SKILL.md missing identity step"; fi
if grep -q 'argument-hint:.*"identity"' "$SKILL"; then pass "argument-hint lists identity"; else fail "argument-hint missing identity"; fi
```

- [ ] **Step 4: Run the full test + doctor**

Run: `bash scripts/test-onboard-identity.sh`
Expected: PASS — `passed: 8  failed: 0`.

Run: `bash scripts/doctor.sh --summary`
Expected: a `▶ test-onboard-identity` line appears with ✅.

- [ ] **Step 5: Commit**

```bash
git add system/skills/onboard/SKILL.md scripts/test-onboard-identity.sh
git commit -m "feat(onboard): add identity step to /onboard (G1/R3)"
```

---

## Self-Review (Sub-plan 3)

- **Spec coverage:** G1 (name/email/git captured, git-config read+confirm, identity as a first-class onboarding step + seeded template) → Tasks 1 & 3. R3 (per-project-type multi-identity routing) → the template's "Identity routing" section + the SKILL.md multi-identity question. The Sub-plan 1 completeness check already covers `identity.md` via the generic `personal/<file>.md` skip-if-done row (no change needed).
- **Placeholder scan:** every step shows the exact template / bash / markdown; no TBD.
- **Type/name consistency:** the template filename `identity.md`, the test's grep targets (`## Name`, `## Email`, `## Git`, `This is an example`, `{{uuid5}}`), and the SKILL.md `6. \`identity.md\`` marker are consistent across all three tasks.
- **Assumptions verified at execution:** (a) `setup-templates.sh` seeds via `user-preferences/*.md` glob (confirmed line 70) so the new template auto-seeds; (b) `check-frontmatter.sh` exempts `user-preferences/*.md` (confirmed line 20) so the `{{uuid5}}` placeholder does not fail the frontmatter hook; (c) the SKILL.md item-5 block matches the post-Sub-plan-2 state (verified before writing this plan).

## Not in this sub-plan

Binding an identity to a space at space-creation time (`new-space.sh --identity/--brand`, R2/R3 space side) and writing git/mail identity into `local/integrations/` automatically are separate refinements (touch `new-space.sh` and the integrations layer) — out of scope here, which delivers the identity *capture* step and template.
