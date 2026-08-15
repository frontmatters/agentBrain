# Onboarding Bak A · Sub-plan 2 — Fixed-choice intake + locale unification

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `/onboard` intake present enum-shaped answers as fixed choices (G5) and unify the conversation-language and UI-locale questions so locale is derived, not asked twice, with an explicit signal for unsupported locales (G6).

**Architecture:** Introduce one small canonical data file `system/skills/onboard/choices.json` that defines which onboarding fields are fixed-choice (with their option sets) and which stay free-text, plus the supported-locale set. `SKILL.md` cites it and presents those fields as numbered pick-lists; a bash test validates the schema and keeps its locale set in sync with the single source (`scripts/lib/_strings.sh`). The agent stays the renderer — no engine — so this is additive and consistent with the focus-based skill contract.

**Tech Stack:** JSON data file, Python (stdlib `json`) for validation, the repo's fixture-based bash test pattern, `scripts/doctor.sh` check-runner, Markdown skill edits.

**Design decision:** a data file (not inline-only prose) is chosen because (a) markdown instructions are not unit-testable — the schema gives TDD a real target, and (b) it is the single source the future CLI/GUI renderers (out of scope here) will reuse. It is deliberately minimal: field → type + options.

---

## File structure

- **Create** `system/skills/onboard/choices.json` — canonical fixed-choice sets + supported locales.
- **Create** `scripts/test-onboard-choices.sh` — validates the schema and its locale/`_strings.sh` consistency.
- **Modify** `scripts/doctor.sh` — add the test to `local_checks` (keeps the schema valid over time).
- **Modify** `system/skills/onboard/SKILL.md` — present fixed choices; fold locale into the language question.

---

### Task 1: choices.json + validation test

**Files:**
- Create: `system/skills/onboard/choices.json`
- Create: `scripts/test-onboard-choices.sh`

- [ ] **Step 1: Write the failing test**

Create `scripts/test-onboard-choices.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# test-onboard-choices.sh — validate system/skills/onboard/choices.json and keep
# its supported-locale set in sync with the single source (scripts/lib/_strings.sh).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHOICES="$ROOT_DIR/system/skills/onboard/choices.json"
STRINGS="$ROOT_DIR/scripts/lib/_strings.sh"
PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

# 1) choices.json is valid JSON with the expected shape
if python3 - "$CHOICES" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert isinstance(d.get("fields"), dict) and d["fields"], "fields missing/empty"
for name, f in d["fields"].items():
    assert f.get("type") in ("choice", "text"), f"{name}: bad type"
    if f["type"] == "choice":
        opts = f.get("options")
        assert isinstance(opts, list) and len(opts) >= 2, f"{name}: choice needs >=2 options"
assert isinstance(d.get("locales", {}).get("supported"), list) and d["locales"]["supported"], "locales.supported missing"
PY
then pass "choices.json valid + well-shaped"; else fail "choices.json invalid"; fi

# 2) supported locales EXACTLY match the _strings.sh normalize case (single source)
STRINGS_CODES="$(sed -n '/# Normalize/,/esac/p' "$STRINGS" | grep -oE '^[[:space:]]*[a-z|]+\)' | head -1 | tr -d ' )' | tr '|' '\n' | sort | paste -sd, -)"
JSON_CODES="$(python3 -c 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1]))["locales"]["supported"])))' "$CHOICES")"
if [ "$STRINGS_CODES" = "$JSON_CODES" ]; then
  pass "supported locales match _strings.sh ($JSON_CODES)"
else
  fail "locale mismatch: choices.json=[$JSON_CODES] vs _strings.sh=[$STRINGS_CODES]"
fi

# 3) the enum fields G5 targets are present and are choices
for field in verbosity autonomy design channel updateMode scope; do
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); f=d["fields"].get(sys.argv[2]); sys.exit(0 if f and f["type"]=="choice" else 1)' "$CHOICES" "$field"; then
    pass "$field is a fixed choice"; else fail "$field missing or not a choice"; fi
done

echo "  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/test-onboard-choices.sh`
Expected: FAIL — `choices.json invalid` (file does not exist yet), non-zero exit.

- [ ] **Step 3: Create the schema**

Create `system/skills/onboard/choices.json`:

```json
{
  "$comment": "Canonical fixed-choice sets for /onboard intake (gap G5). SKILL.md presents type:choice fields as numbered pick-lists; type:text stay free-text. locales.supported must equal the scripts/lib/_strings.sh normalize case (gap G6).",
  "fields": {
    "language":   { "type": "choice", "file": "communication.md", "options": ["English", "Nederlands", "Mixed"], "derivesLocale": true },
    "verbosity":  { "type": "choice", "file": "communication.md", "options": ["concise", "detailed", "depends on topic"] },
    "askFirst":   { "type": "choice", "file": "communication.md", "options": ["ask before acting", "just do trivial things"] },
    "autonomy":   { "type": "choice", "file": "workflow.md", "options": ["ask often", "only for blockers", "full autonomy"] },
    "design":     { "type": "choice", "file": "design-philosophy.md", "options": ["dark", "light", "both"] },
    "decision":   { "type": "choice", "file": "decision-making.md", "options": ["pragmatic", "thorough", "move fast"] },
    "channel":    { "type": "choice", "options": ["stable", "prerelease", "edge"] },
    "updateMode": { "type": "choice", "options": ["ask", "notify", "auto", "off"] },
    "scope":      { "type": "choice", "options": ["personal only", "personal + organization", "personal + organization + team"] },
    "os":         { "type": "text", "file": "tech-stack.md" },
    "editor":     { "type": "text", "file": "tech-stack.md" },
    "languages":  { "type": "text", "file": "tech-stack.md" },
    "hosting":    { "type": "text", "file": "tech-stack.md" }
  },
  "locales": {
    "supported": ["en", "nl"],
    "note": "Single source: scripts/lib/_strings.sh normalize case. An unsupported code -> tell the user and offer /add-locale."
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash scripts/test-onboard-choices.sh`
Expected: PASS — `passed: 8  failed: 0` (1 shape + 1 locale-sync + 6 enum-field checks).

- [ ] **Step 5: Commit**

```bash
git add system/skills/onboard/choices.json scripts/test-onboard-choices.sh
git commit -m "feat(onboard): add canonical fixed-choice schema for intake (G5/G6)"
```

---

### Task 2: Wire the schema test into `doctor`

**Files:**
- Modify: `scripts/doctor.sh` (the `local_checks=(` array, line 100)

- [ ] **Step 1: Write the failing assertion**

Append to `scripts/test-onboard-choices.sh`, just before the final `echo "  passed: ..."` line:

```bash
# 4) doctor runs the schema validation
if grep -q 'test-onboard-choices.sh' "$ROOT_DIR/scripts/doctor.sh"; then
  pass "doctor runs onboard-choices test"; else fail "doctor does not run onboard-choices test"; fi
```

- [ ] **Step 2: Run to verify the new assertion fails**

Run: `bash scripts/test-onboard-choices.sh`
Expected: prints `✗ doctor does not run onboard-choices test`, exits non-zero.

- [ ] **Step 3: Add to `local_checks`**

In `scripts/doctor.sh`, inside the `local_checks=(` array (line 100), add this line right after the existing `check-onboarding.sh` entry:

```bash
	"bash scripts/test-onboard-choices.sh"   # onboarding fixed-choice schema (G5/G6)
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test-onboard-choices.sh`
Expected: PASS — `passed: 9  failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add scripts/doctor.sh scripts/test-onboard-choices.sh
git commit -m "feat(doctor): validate onboarding fixed-choice schema (G5/G6)"
```

---

### Task 3: Present fixed choices + unify locale in SKILL.md

**Files:**
- Modify: `system/skills/onboard/SKILL.md`

- [ ] **Step 1: Add the fixed-choice presentation rule + mark the Step-1 questions**

In `system/skills/onboard/SKILL.md`, replace the block that currently reads (starts at "Ask questions in this order:"):

```markdown
Ask questions in this order:

1. `communication.md`
   - "What language do you prefer for conversation? (e.g. English, Dutch, mixed)"
   - "How verbose should I be? (concise / detailed / depends on topic)"
   - "Should I ask before acting, or just do it for trivial decisions?"
2. `tech-stack.md`
   - "What's your primary OS and editor?"
   - "What languages and frameworks do you use most?"
   - "Where do you host code? (GitHub, GitLab, self-hosted, etc.)"
   - "Any infrastructure preferences? (Docker, cloud provider, database, etc.)"
3. `workflow.md`
   - "Where do your projects live on disk?"
   - "How autonomous should I be? (ask often / only for blockers / full autonomy)"
   - "Any shell or tooling preferences? (zsh, bash, package managers, etc.)"
4. `design-philosophy.md`
   - "Do you have a preferred visual style? (minimal, Material, custom design system, etc.)"
   - "Dark mode, light mode, or both?"
   - "Any icon/typography preferences?"
5. `decision-making.md`
   - "How do you approach technical decisions? (pragmatic, thorough, move fast, etc.)"
   - "Build vs buy — do you prefer libraries or custom code?"
   - "How important is backwards compatibility vs. clean breaks?"
```

with:

```markdown
Ask questions in this order. Questions marked **(choice)** have a fixed answer
set defined in `system/skills/onboard/choices.json` — present those as a short
numbered pick-list, accept the number or the label, treat the first option as
the default (a bare Enter selects it), and confirm the resolved value back.
Questions without **(choice)** stay open free-text. Never force a pick-list onto
a free-text question.

1. `communication.md`
   - **(choice · language)** "What language do you prefer for conversation?" — options: English / Nederlands / Mixed. This also sets your UI-locale (see Step 5 — do not ask locale again). If the chosen language maps to a locale code that is **not** in `choices.json` `locales.supported`, say it is not supported yet and offer to run `/add-locale`, then continue in English meanwhile.
   - **(choice · verbosity)** "How verbose should I be?" — concise / detailed / depends on topic.
   - **(choice · askFirst)** "Should I ask before acting, or just do trivial things?"
2. `tech-stack.md`
   - "What's your primary OS?" then "your editor?" (ask atomically, not combined)
   - "What languages and frameworks do you use most?"
   - "Where do you host code? (GitHub, GitLab, self-hosted, etc.)"
   - "Any infrastructure preferences? (Docker, cloud provider, database, etc.)"
3. `workflow.md`
   - "Where do your projects live on disk?"
   - **(choice · autonomy)** "How autonomous should I be?" — ask often / only for blockers / full autonomy.
   - "Any shell or tooling preferences? (zsh, bash, package managers, etc.)"
4. `design-philosophy.md`
   - "Do you have a preferred visual style? (minimal, Material, custom design system, etc.)"
   - **(choice · design)** "Dark mode, light mode, or both?"
   - "Any icon/typography preferences?"
5. `decision-making.md`
   - **(choice · decision)** "How do you approach technical decisions?" — pragmatic / thorough / move fast.
   - "Build vs buy — do you prefer libraries or custom code?"
   - "How important is backwards compatibility vs. clean breaks?"
```

- [ ] **Step 2: Fold locale into the language question (Step 5)**

In `system/skills/onboard/SKILL.md`, at the start of `### Step 5 — Locale`, replace the first paragraph:

```markdown
Show the currently resolved locale and offer to change it:
```

with:

```markdown
The UI-locale is **derived from the Step 1 language question** — do not ask for
it again in walk-all mode. Only prompt here when the user runs `/onboard locale`
directly, or explicitly wants the UI-locale to differ from their conversation
language. In those cases, show the currently resolved locale and offer to change it:
```

- [ ] **Step 3: Mark the channel/update Step 6 questions as choices**

In `system/skills/onboard/SKILL.md`, in `### Step 6 — Release channel & updates`, immediately before the line `Ask two questions:`, insert:

```markdown
Both questions below are **(choice)** — present them as numbered pick-lists per
`system/skills/onboard/choices.json` (`channel`, `updateMode`).
```

- [ ] **Step 4: Add a structural assertion to the test**

Append to `scripts/test-onboard-choices.sh`, before the final `echo "  passed: ..."` line:

```bash
# 5) SKILL.md references the schema and folds locale into the language step
SKILL="$ROOT_DIR/system/skills/onboard/SKILL.md"
if grep -q 'choices.json' "$SKILL"; then pass "SKILL.md cites choices.json"; else fail "SKILL.md does not cite choices.json"; fi
if grep -q 'derived from the Step 1 language' "$SKILL"; then pass "SKILL.md derives locale (G6)"; else fail "SKILL.md still asks locale separately"; fi
```

- [ ] **Step 5: Run the full test + doctor**

Run: `bash scripts/test-onboard-choices.sh`
Expected: PASS — `passed: 11  failed: 0`.

Run: `bash scripts/doctor.sh --summary`
Expected: a `▶ test-onboard-choices` line appears with ✅.

- [ ] **Step 6: Commit**

```bash
git add system/skills/onboard/SKILL.md scripts/test-onboard-choices.sh
git commit -m "feat(onboard): present fixed choices + derive locale in SKILL.md (G5/G6)"
```

---

## Self-Review (Sub-plan 2)

- **Spec coverage:** G5 (enum answers as fixed choices) → `choices.json` + SKILL.md `(choice)` markers (Tasks 1, 3). G6 (locale derived, not duplicated; unsupported-locale signal) → SKILL.md Step-1 language note + Step-5 fold + `locales.supported` sync test (Tasks 1, 3). Atomic OS/editor split (a small G5-adjacent fix noted by the CLI-UX peer) → Step 2 edit.
- **Placeholder scan:** every step shows the exact JSON / bash / markdown; no TBD.
- **Type/name consistency:** field names in `choices.json` (`verbosity`, `autonomy`, `design`, `channel`, `updateMode`, `scope`, `askFirst`, `decision`) are the same names the test checks and the SKILL.md `(choice · <name>)` markers reference.
- **Assumption to verify at execution:** the `_strings.sh` normalize case currently lists `nl|en`; the test derives the codes from it, so if `/add-locale` later widens the set, the test enforces that `choices.json` is updated in lockstep (intended behavior, not a bug).

---

## Not in this sub-plan

Terminal fixed-choice *rendering* (arrow-select / number-key / non-TTY fallback) belongs to the CLI/GUI renderers, which are a separate future plan. Here the agent presents the choices conversationally; `choices.json` is the shared source those renderers will consume later.
