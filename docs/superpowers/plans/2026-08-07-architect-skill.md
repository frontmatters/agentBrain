# `/architect` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `/architect` skill in the agentBrain vault: a template-driven, evidence-gated architecture-analysis workflow executable by a cheaper model, with deterministic form validation, EN/NL output, mandatory mermaid diagrams, and optional HTML render + peer review.

**Architecture:** The skill is a directory in the private vault (`~/agentBrain/local/skills/architect/`) containing a SKILL.md (workflow + hard gates), five phase templates the model fills in, and a bash 3.2-compatible `validate.sh` that deterministically checks form (sections, evidence paths, mermaid count, decision-record completeness). HTML rendering delegates to the existing `brain-explain` skill; design review delegates to the existing `peer-review` skill. Spec: `docs/superpowers/specs/2026-08-07-architect-skill-design.md`.

**Tech Stack:** Bash (stock macOS 3.2 — no `mapfile`, no associative arrays), Markdown templates, mermaid, agentBrain conventions (`new-note.sh`, vault git repo, `~/.claude/skills` symlinks).

**Repos involved:**
- Vault (private git repo): `~/.agentBrain/vault` — all skill files live here under `local/skills/architect/`. Commit with `git -C ~/.agentBrain/vault …`. The path `~/agentBrain/local/` is a symlink to this vault; both spellings reach the same files.
- `agentBrain-dev` (public): only this plan + spec live here. Never put client/project names in these public files.

**Fixed language-neutral tokens** (used by templates AND validate.sh — never translate these, whatever `--lang` is):
- Section anchors: `## Recon`, `## Building Blocks`, `## Constraints`, `## Decisions`, `## Open Questions`
- Constraint lenses: `### Egress`, `### Data & Storage`, `### Secrets`, `### Identity & Access`, `### Compliance`, `### Operations`
- Field markers: `evidence:`, `abort-condition:`, `⚠ Open`, `**Option N:**`, `**Recommendation:**`, `### Decision:`

---

### Task 1: Failing test for `validate.sh` (TDD)

**Files:**
- Create: `~/.agentBrain/vault/skills/architect/scripts/test-validate.sh`

Note: inside the vault repo the tree starts at the vault root, so `local/skills/architect/` as seen from `~/agentBrain/` equals `skills/architect/` inside `~/.agentBrain/vault/`. Verify with `ls ~/.agentBrain/vault/skills/` first; if the vault root instead contains a `local/` directory, prefix all vault paths below with `local/`.

- [ ] **Step 1: Confirm vault layout**

Run: `ls ~/.agentBrain/vault/ | head -20`
Expected: directories like `skills`, `learnings`, `projects` (no `local/` prefix) — OR a `local/` directory (then prefix all paths below).

- [ ] **Step 2: Create the skill directory skeleton**

```bash
mkdir -p ~/.agentBrain/vault/skills/architect/scripts ~/.agentBrain/vault/skills/architect/templates
```

- [ ] **Step 3: Write the test script**

Create `~/.agentBrain/vault/skills/architect/scripts/test-validate.sh` with exactly this content:

````bash
#!/usr/bin/env bash
# test-validate.sh — tests for the /architect dossier form-checker.
# Builds fixture dossiers in a tmpdir and asserts validate.sh pass/fail.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
validate="$here/validate.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { echo "ok - $1"; pass=$((pass+1)); }
bad() { echo "NOT OK - $1"; fail=$((fail+1)); }

# --- fixture repo with real files for evidence checks ---
mkdir -p "$tmp/repo/apps/daemon/src"
touch "$tmp/repo/apps/daemon/src/server.ts" "$tmp/repo/package.json"

# --- valid dossier ---
cat > "$tmp/valid.md" <<EOF
---
title: Architecture — Fixture
repo: $tmp/repo
---

## Recon

| Concern | File / location | How found |
|---|---|---|
| API server | \`apps/daemon/src/server.ts\` | grep |

evidence: \`apps/daemon/src/server.ts\`

## Building Blocks

\`\`\`mermaid
flowchart LR
  A[Web] --> B[Daemon]
\`\`\`

| Component | Where | Role | Trust level |
|---|---|---|---|
| Daemon | \`apps/daemon/src/server.ts\` | API owner | privileged |

evidence: \`apps/daemon/src/server.ts\`

## Constraints

\`\`\`mermaid
flowchart TD
  B[Daemon] --> X[External API]
\`\`\`

### Egress
One outbound call to the model provider.
evidence: \`package.json\`

### Data & Storage
State lives in a local data dir.
⚠ Open: encryption at rest unconfirmed.

### Secrets
Keys in a config file today.
⚠ Open: vault integration missing.

### Identity & Access
No auth layer exists yet.
⚠ Open: SSO provider unknown.

### Compliance
GDPR applies to any personal data in prompts.
⚠ Open: data-classification ceiling unknown.

### Operations
No structured logging yet.
⚠ Open: SIEM target unknown.

## Decisions

### Decision: where should auth live?

**Context:** the tool has no login; upstream updates must stay mergeable.

**Option 1:** modify the core — fast, but causes fork rot.

**Option 2:** host-shell in front — slower, upgrade-safe.

**Recommendation:** Option 2, host-shell.

abort-condition: chosen IdP protocol unsupported by the shell.

## Open Questions

| # | ⚠ Open | Who/what can answer |
|---|---|---|
| 1 | IdP protocol | customer IT |
EOF

# --- invalid fixtures, one defect each ---

# missing a required section
sed '/^## Decisions/,/^## Open Questions/d' "$tmp/valid.md" > "$tmp/no-decisions.md"

# placeholder text
sed 's/One outbound call to the model provider./TBD/' "$tmp/valid.md" > "$tmp/has-tbd.md"

# only one mermaid block
awk 'BEGIN{skip=0} /^```mermaid/ && ++c==2 {skip=1} skip && /^```$/ {skip=0; next} !skip' "$tmp/valid.md" > "$tmp/one-mermaid.md"

# evidence path that does not exist
sed 's|evidence: `package.json`|evidence: `does/not/exist.ts`|' "$tmp/valid.md" > "$tmp/bad-evidence.md"

# decision with one option and no abort-condition
sed -e '/\*\*Option 2:\*\*/d' -e '/^abort-condition:/d' "$tmp/valid.md" > "$tmp/bad-decision.md"

# --- assertions ---
[ -x "$validate" ] || { echo "NOT OK - validate.sh missing or not executable"; exit 1; }

if "$validate" "$tmp/valid.md" >/dev/null 2>&1; then ok "valid dossier passes"; else bad "valid dossier should pass"; "$validate" "$tmp/valid.md"; fi

for f in no-decisions has-tbd one-mermaid bad-evidence bad-decision; do
  if "$validate" "$tmp/$f.md" >/dev/null 2>&1; then bad "$f should fail"; else ok "$f fails as expected"; fi
done

echo "---"
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 4: Make it executable and run it — expect failure**

Run:
```bash
chmod +x ~/.agentBrain/vault/skills/architect/scripts/test-validate.sh
~/.agentBrain/vault/skills/architect/scripts/test-validate.sh
```
Expected: `NOT OK - validate.sh missing or not executable`, exit code 1.

- [ ] **Step 5: Commit to the vault repo**

```bash
git -C ~/.agentBrain/vault add skills/architect/scripts/test-validate.sh
git -C ~/.agentBrain/vault commit -m "test(architect): fixture-based tests for dossier form-checker"
```

---

### Task 2: Implement `validate.sh`

**Files:**
- Create: `~/.agentBrain/vault/skills/architect/scripts/validate.sh`

- [ ] **Step 1: Write the implementation**

Create `~/.agentBrain/vault/skills/architect/scripts/validate.sh` with exactly this content (bash 3.2-safe: no `mapfile`, no associative arrays, `set -u` only):

````bash
#!/usr/bin/env bash
# validate.sh — deterministic form-check for /architect dossiers.
# Usage: validate.sh <dossier.md> [repo-root]
# Exit 0 = pass, 1 = findings, 2 = usage error.
# Checks FORM only (sections, evidence paths, diagrams, decision completeness);
# thinking quality is the job of --peer-review, not this script.
set -u

dossier="${1:-}"
repo_root="${2:-}"
[ -z "$dossier" ] && { echo "usage: validate.sh <dossier.md> [repo-root]" >&2; exit 2; }
[ -f "$dossier" ] || { echo "FAIL dossier not found: $dossier" >&2; exit 1; }

failed=0
err() { echo "FAIL $1"; failed=1; }

# repo root: arg 2 wins, else frontmatter 'repo:' line
if [ -z "$repo_root" ]; then
  repo_root="$(awk 'f && /^---$/{exit} /^---$/{f=1;next} f && sub(/^repo:[[:space:]]*/,""){print;exit}' "$dossier")"
fi
case "$repo_root" in "~"*) repo_root="$HOME${repo_root#\~}";; esac

# 1 — required section anchors (language-neutral tokens, never translated)
for h in "## Recon" "## Building Blocks" "## Constraints" "## Decisions" "## Open Questions"; do
  grep -q "^$h" "$dossier" || err "missing section: $h"
done

# 2 — the six constraint lenses
for lens in "Egress" "Data & Storage" "Secrets" "Identity & Access" "Compliance" "Operations"; do
  grep -q "^### $lens" "$dossier" || err "missing constraint lens: ### $lens"
done

# 3 — no placeholders
ph="$(grep -nE 'TBD|TODO' "$dossier" || true)"
[ -n "$ph" ] && err "placeholders found:
$ph"

# 4 — at least two mermaid diagrams
mcount="$(grep -c '^```mermaid' "$dossier" || true)"
[ "$mcount" -ge 2 ] || err "need >=2 mermaid diagrams, found $mcount"

# 5 — evidence: at least 3 markers; every backticked path must exist.
#     Path form:  evidence: `relative/or/abs/path[:line]`
#     Non-path evidence (command output, prose) is allowed and not path-checked.
ev_total="$(grep -c 'evidence:' "$dossier" || true)"
[ "$ev_total" -ge 3 ] || err "need >=3 evidence: markers, found $ev_total"
bad_ev="$(sed -n 's/.*evidence:[[:space:]]*`\([^`]*\)`.*/\1/p' "$dossier" | while IFS= read -r ref; do
  p="$ref"
  case "$p" in *:[0-9]*) p="${p%:*}";; esac
  case "$p" in
    /*) t="$p" ;;
    "~"*) t="$HOME${p#\~}" ;;
    *) t="$repo_root/$p" ;;
  esac
  [ -e "$t" ] || printf '%s\n' "$ref"
done)"
[ -n "$bad_ev" ] && err "evidence paths not found (repo-root=$repo_root):
$bad_ev"

# 6 — decision records: >=1 record; each needs >=2 options and >=1 abort-condition
dec_count="$(grep -c '^### Decision:' "$dossier" || true)"
[ "$dec_count" -ge 1 ] || err "no decision records (### Decision:) found"
baddec="$(awk '
  function flush() { if (name != "" && (opts < 2 || aborts < 1)) printf "%s (options=%d, abort-conditions=%d)\n", name, opts, aborts }
  /^### Decision:/ { flush(); name=$0; opts=0; aborts=0; next }
  /^## / { flush(); name="" }
  name != "" && /\*\*Option / { opts++ }
  name != "" && /^abort-condition:/ { aborts++ }
  END { flush() }
' "$dossier")"
[ -n "$baddec" ] && err "incomplete decision records:
$baddec"

# 7 — no near-empty top-level sections (>=2 non-empty lines before the next ##)
thin="$(awk '
  /^## /{ if (sec != "" && n < 2) print sec; sec=$0; n=0; next }
  sec != "" && NF > 0 { n++ }
  END { if (sec != "" && n < 2) print sec }
' "$dossier")"
[ -n "$thin" ] && err "sections with fewer than 2 content lines:
$thin"

if [ "$failed" -eq 0 ]; then
  echo "OK dossier passes all form checks"
else
  exit 1
fi
````

- [ ] **Step 2: Make executable, run the tests — expect all green**

Run:
```bash
chmod +x ~/.agentBrain/vault/skills/architect/scripts/validate.sh
~/.agentBrain/vault/skills/architect/scripts/test-validate.sh
```
Expected: 6 × `ok - …`, ending `passed=6 failed=0`, exit 0.
If a fixture unexpectedly passes/fails, fix `validate.sh` (not the test) unless the fixture itself is malformed.

- [ ] **Step 3: Commit**

```bash
git -C ~/.agentBrain/vault add skills/architect/scripts/validate.sh
git -C ~/.agentBrain/vault commit -m "feat(architect): deterministic dossier form-checker (bash 3.2)"
```

---

### Task 3: The five phase templates

**Files:**
- Create: `~/.agentBrain/vault/skills/architect/templates/00-recon.md`
- Create: `~/.agentBrain/vault/skills/architect/templates/01-building-blocks.md`
- Create: `~/.agentBrain/vault/skills/architect/templates/02-constraints.md`
- Create: `~/.agentBrain/vault/skills/architect/templates/03-decision.md`
- Create: `~/.agentBrain/vault/skills/architect/templates/04-open-questions.md`

Templates are skeletons the executing model copies into the dossier and fills in. Instructional HTML comments guide the model; they must be deleted in the final dossier (they'd trip the thin-section check anyway if left as the only content). Section anchors and field markers are fixed tokens — prose language follows `--lang`.

- [ ] **Step 1: Write `templates/00-recon.md`**

````markdown
## Recon

<!-- GATE: complete this table BEFORE any later phase. Map first, conclude later.
     One row per concern (entrypoint, config, data dir, auth, egress, build).
     "How found" must be a real command you ran (grep/ls/find), not a guess. -->

| Concern | File / location | How found (command) |
|---|---|---|
| <concern> | `<path>` | `<command>` |

evidence: `<path-of-most-load-bearing-file>`
````

- [ ] **Step 2: Write `templates/01-building-blocks.md`**

````markdown
## Building Blocks

<!-- The mental model first: one mermaid flowchart of components + data flow.
     Then the table. Trust level ∈ {privileged, delegated, data, ui, external}.
     Every row needs an evidence: path. Name explicitly what is privileged
     (the blast radius) and what is delegated to third parties. -->

```mermaid
flowchart LR
  %% components + data flow
```

| Component | Where | Role | Trust level | Evidence |
|---|---|---|---|---|
| <name> | `<path>` | <role> | <trust> | evidence: `<path>` |
````

- [ ] **Step 3: Write `templates/02-constraints.md`**

````markdown
## Constraints

<!-- One mermaid diagram of egress/zones, then the six lenses.
     Every lens gets facts WITH evidence:, or an explicit "⚠ Open: …" line.
     An empty lens is forbidden; "⚠ Open" is a valid and honest answer. -->

```mermaid
flowchart TD
  %% egress / zone diagram: what talks to what, across which boundary
```

### Egress
<!-- outbound connections: destination, payload class, source file -->

### Data & Storage
<!-- where state lives, what is relocatable/encrypted -->

### Secrets
<!-- where credentials live, how injected -->

### Identity & Access
<!-- authN/authZ, roles, enforcement point (server-side or UI-only?) -->

### Compliance
<!-- applicable regimes (GDPR/DORA/…) and the evidence each expects -->

### Operations
<!-- logging, monitoring, health, incident path -->
````

- [ ] **Step 4: Write `templates/03-decision.md`**

````markdown
### Decision: <the design question>

<!-- One record per design question, inside the "## Decisions" section.
     >=2 real options with trade-offs. Recommendation picks one and says why.
     >=1 abort-condition: the observable signal that invalidates this decision. -->

**Context:** <what forces this decision; cite evidence: where possible>

**Option 1:** <name> — <trade-offs>

**Option 2:** <name> — <trade-offs>

**Recommendation:** <chosen option + why, in 2-4 sentences>

abort-condition: <observable trigger that reopens this decision>
````

- [ ] **Step 5: Write `templates/04-open-questions.md`**

````markdown
## Open Questions

<!-- The ⚠ Open ledger. An open question is a VALID result — never fill in
     what cannot be known from the repo or the vault. Every row names who or
     what can answer it. Collect every "⚠ Open" from the lenses here too. -->

| # | ⚠ Open | Who/what can answer |
|---|---|---|
| 1 | <question> | <owner/source> |
````

- [ ] **Step 6: Verify and commit**

Run: `ls ~/.agentBrain/vault/skills/architect/templates/`
Expected: the five files above.

```bash
git -C ~/.agentBrain/vault add skills/architect/templates/
git -C ~/.agentBrain/vault commit -m "feat(architect): five phase templates with fixed anchors and evidence markers"
```

---

### Task 4: SKILL.md

**Files:**
- Create: `~/.agentBrain/vault/skills/architect/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Create `~/.agentBrain/vault/skills/architect/SKILL.md` with exactly this content:

````markdown
---
name: architect
description: >
  Full-cycle architecture analysis of an existing system, executable by a
  cheaper model: identify building blocks, map constraints through six fixed
  lenses (egress, data, secrets, identity, compliance, operations), take
  design decisions as decision records with abort-conditions, and keep an
  explicit open-questions ledger. Every claim needs evidence (path/grep/
  command output); a deterministic validate.sh gates delivery. Use when the
  user asks for "architectuur-analyse", "bouwstenen identificeren", "what is
  needed to run X on Y", "wat is er nodig om X op Y te runnen", a hosting/
  deployment design, a decision record, or an architecture dossier for an
  existing repo. Not for greenfield design (use brainstorming) or code
  distillation (use scanman).
argument-hint: <repo-path or project-slug> [design question] [--peer-review] [--lang en|nl] [--html]
user-invocable: true
resources:
  - templates/00-recon.md
  - templates/01-building-blocks.md
  - templates/02-constraints.md
  - templates/03-decision.md
  - templates/04-open-questions.md
  - scripts/validate.sh
---

# Architect

Produce an evidence-gated architecture dossier for an existing system. The
dossier is one markdown file assembled from the five templates, in this exact
section order: Recon → Building Blocks → Constraints → Decisions → Open
Questions.

## Hard gates (non-negotiable)

1. **Map first, conclude later.** Phase 0 (Recon) blocks everything: no
   building-block table, no decisions, until the recon table is complete.
2. **Every factual claim carries `evidence:`** — a backticked repo path
   (checked for existence by validate.sh), a grep hit, or command output.
3. **Unknown → `⚠ Open`.** Never write an assumption as a fact. An open
   question is a valid result.
4. **Deliver only after `scripts/validate.sh <dossier> [repo-root]` exits 0.**
   Presenting with a failing validation is an auto-fail: fix, re-run, repeat.
5. **Fixed tokens are never translated**: section anchors (`## Recon`,
   `## Building Blocks`, `## Constraints`, `## Decisions`, `## Open
   Questions`), lenses (`### Egress`, `### Data & Storage`, `### Secrets`,
   `### Identity & Access`, `### Compliance`, `### Operations`), and markers
   (`evidence:`, `abort-condition:`, `⚠ Open`, `**Option N:**`,
   `**Recommendation:**`, `### Decision:`).

## Language

Default prose language is **English** (dossiers are handover material). With
`--lang nl` — or when the user asks for the session language — write the prose
in that language. Tokens stay English per gate 5.

## Workflow

### Phase 0 — Recon [blocks all later phases]

1. `brain_search` the topic first (vary terms). An existing dossier/explainer
   is input, never ignored. Empty search → filesystem fallback per the
   lookup-first protocol.
2. Map the repo with `ls`/`grep` (grep-first per concern) until the table in
   `templates/00-recon.md` is complete: entrypoints, config, data dir, auth,
   egress, build.
3. No access to the repo/path → stop with a clear message. Never produce a
   fantasy analysis.

### Phase 1 — Building Blocks

Fill `templates/01-building-blocks.md`: the mermaid mental model (components +
data flow) and the component table. Name explicitly what is privileged (the
blast radius) and what is delegated to third parties.

### Phase 2 — Constraints

Fill `templates/02-constraints.md`: the egress/zone mermaid diagram, then all
six lenses. Every lens: facts with `evidence:` or an explicit `⚠ Open:` line.

### Phase 3 — Decisions

One `templates/03-decision.md` record per design question the user asked (or
that the analysis surfaced). Context → ≥2 options with trade-offs →
recommendation → ≥1 `abort-condition:`.

With `--peer-review`: send the draft Decisions section through the
`peer-review` skill and process the verdict before delivery. A negative
verdict → revise the record, or include the disagreement explicitly in the
record. Never silently ignore it.

### Phase 4 — Open Questions

Fill `templates/04-open-questions.md`: collect every `⚠ Open` into the ledger;
each row names who or what can answer it.

### Delivery

1. Create the dossier note:
   `bash ~/agentBrain/scripts/new-note.sh project local/projects/<slug>/architecture "Architecture — <name>"`
   Then add one line `repo: <absolute repo path>` to the frontmatter (directly
   under `id:`), and paste the assembled dossier below it.
2. Validate: `bash ~/agentBrain/local/skills/architect/scripts/validate.sh
   ~/agentBrain/local/projects/<slug>/architecture.md` — repeat until it
   prints `OK`.
3. Copy into the target repo: `docs/architecture/<YYYY-MM-DD>-<topic>.md`
   (create the directory if needed). The vault note is the source of truth.
4. With `--html` (or on request): render via the `brain-explain` skill (the
   dossier already carries the two mermaid diagrams; markdown stays the
   source, never hand-edit the HTML).
5. Report to the user: dossier path (vault + repo copy), validation result,
   the decision recommendations in one line each, and the open questions.

## What this skill is not

- Not greenfield design (use brainstorming → writing-plans).
- Not code distillation/redesign (use scanman).
- Not implementation: it delivers a dossier, not code changes.
````

- [ ] **Step 2: Verify frontmatter fields**

Run: `head -30 ~/.agentBrain/vault/skills/architect/SKILL.md | grep -E '^(name|argument-hint|user-invocable):'`
Expected: the three lines `name: architect`, `argument-hint: …`, `user-invocable: true`.

- [ ] **Step 3: Commit**

```bash
git -C ~/.agentBrain/vault add skills/architect/SKILL.md
git -C ~/.agentBrain/vault commit -m "feat(architect): SKILL.md — five-phase evidence-gated workflow"
```

---

### Task 5: Wire the skill into Claude Code + sync the vault

**Files:**
- Create: symlink `~/.claude/skills/architect` → `~/agentBrain/local/skills/architect`

- [ ] **Step 1: Symlink (same pattern as deep-dive/scanman)**

```bash
ln -sfn ~/agentBrain/local/skills/architect ~/.claude/skills/architect
ls -la ~/.claude/skills/architect
```
Expected: `~/.claude/skills/architect -> $HOME/agentBrain/local/skills/architect`, and `ls ~/.claude/skills/architect/` shows SKILL.md, templates/, scripts/.

- [ ] **Step 2: Sync the private vault to Gitea**

Run: `bash ~/agentBrain/scripts/sync-agentbrain-local.sh`
Expected: pushes the three vault commits; exit 0. If it prompts for setup, report to the user instead of improvising credentials.

- [ ] **Step 3: Smoke-check discoverability**

The skill appears in new sessions after restart. In this session, verify the files resolve through the alias path:
Run: `bash ~/agentBrain/local/skills/architect/scripts/test-validate.sh`
Expected: `passed=6 failed=0`.

---

### Task 6: Acceptance test — cheap-model dry run against the benchmark

No files created in the repos; output lands in the vault under a scratch slug.

- [ ] **Step 1: Resolve the benchmark case**

`brain_search` for the benchmark case named in the spec's acceptance section (the client dossier this workflow came from — hosting explainer + project index in the vault). Note its repo path and slug. Do not write the client name into any public repo file.

- [ ] **Step 2: Dispatch a cheaper model with the skill**

Use the Agent tool (`subagent_type: general-purpose`, `model: sonnet`) with this prompt (fill in the two placeholders from Step 1):

```
Read ~/agentBrain/local/skills/architect/SKILL.md and follow it exactly.
Target repo: <repo-path>. Design question: "what is needed to host this
system at an external managed provider?". Flags: none (no --peer-review,
default language EN). Deliver the dossier to
local/projects/architect-acceptance-test/architecture.md in the vault and
run validate.sh on it until it passes. Return: the dossier path, the
validate.sh output, and your building-blocks table.
```

- [ ] **Step 3: Verify form**

Run: `bash ~/agentBrain/local/skills/architect/scripts/validate.sh ~/agentBrain/local/projects/architect-acceptance-test/architecture.md`
Expected: `OK dossier passes all form checks`.

- [ ] **Step 4: Verify substance against the benchmark**

Compare the produced dossier against the benchmark dossier from Step 1: building blocks (components + trust levels), constraint lenses, open questions. Success criterion from the spec: ≈ agreement on building blocks, constraints, and open questions. Present the comparison to the user as a short table (found / missed / extra) — the user is the judge.

- [ ] **Step 5: Clean up or keep**

Ask the user: keep `local/projects/architect-acceptance-test/` as a worked example, or remove it (`/brain-forget`). Then record the result: if the run passed, note in the vault (via `/save-learning`) that the skill passed acceptance run 1 of 2 (the 2×-rule for promotion to `system/skills/`).

---

## Self-review notes

- Spec coverage: five phases (Tasks 3-4), evidence rules + validate.sh (Tasks 1-2), language option (SKILL.md Language section), ≥2 mermaid enforced (validate check 4), `--html` via brain-explain and `--peer-review` via peer-review skill (SKILL.md Delivery/Phase 3), output contract vault + repo copy (SKILL.md Delivery), acceptance test (Task 6), local-first placement + 2×-promotion note (Task 6 Step 5). No gaps found.
- Token consistency: section anchors, lens names, and markers are identical across test fixtures (Task 1), validate.sh (Task 2), templates (Task 3), and SKILL.md gate 5 (Task 4).
- Placeholders: the literal strings scanned for by check 3 appear in this plan only inside fixture/check code where they are data, not instructions.
