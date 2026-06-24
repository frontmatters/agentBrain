---
name: refactor-brain
description: Plan and execute safe agentBrain refactors such as file renames, path migrations, and reference updates. Always plans first and requires explicit confirmation before changes.
type: skill
tags: [refactoring, maintenance, migration, naming]
user-invocable: true
resources:
  - system/rules.md
  - scripts/check-path-naming.sh
  - scripts/doctor.sh
  - scripts/privacy-scan.sh
---

# Refactor Brain

Perform structured changes to agentBrain with safety guarantees.

Use for:

- File renames with reference updates
- Naming migrations toward lowercase/kebab-case
- Directory moves with cross-reference handling
- Splitting/merging notes while preserving frontmatter
- Batch changes that need validation

Do **not** use this skill to silently migrate paths during onboarding or setup. Refactors are explicit maintenance operations.

## Core policy

- **Plan before execute** — always show the full plan first.
- **Ask for confirmation** before changing files.
- **Never delete information** — rename, move, or archive; do not discard content.
- **Preserve frontmatter** — keep `id`, `tags`, `type`, `status`, `confidence`, and history.
- **Update references** — content links, scripts, skill `resources:`, docs, and README references.
- **Validate after changes** — run naming, privacy, and doctor checks where applicable.
- **Self-heal after refactors** — this skill must update and validate its own references when affected.

## Self-update rule

`refactor-brain` participates in every reference search, including this file:

```text
system/skills/refactor-brain/SKILL.md
```

When a refactor changes paths, naming policy, validation commands, or skill locations:

1. Include this `SKILL.md` in reference updates.
2. Update this skill's `resources:` block and examples if affected.
3. Do not rename or move the `refactor-brain` skill unless explicitly listed in the confirmed plan.
4. After executing changes that touch this skill, re-read this `SKILL.md` before continuing any remaining refactor steps.
5. Validate that the skill still describes the current repository layout and commands.

In short: after the repo is refactored, `refactor-brain` must fix its own instructions so it remains usable for the next refactor.

## Naming policy context

Current public paths use lowercase/kebab-case:

```text
system/
learnings/
projects/
templates/
sessions/
daily-notes/
user-preferences/
youtube-knowledge/
```

Do not change public paths casually. A public path migration is a compatibility-sensitive change and should be a dedicated prerelease/migration.

New `local/` content must be lowercase/kebab-case:

```text
local/projects/my-project/
local/preferences/git-config.md
local/integrations/azure-devops.md
local/security/gitea.md
```

## Invocation

`/refactor-brain <goal>`

Examples:

- `/refactor-brain plan lowercase migration for User Preferences only`
- `/refactor-brain rename local/preferences/Tech Stack.md to local/preferences/tech-stack.md`
- `/refactor-brain move old integration notes into local/integrations/`

## Steps

### 1. Identify scope

- Ask for the exact refactor goal if unclear.
- Identify files/directories involved.
- Separate public paths from `local/` paths.
- Warn when the scope includes public folder renames or convention filenames.

### 2. Inventory current state

Use safe read-only commands first:

```bash
find . -maxdepth 3 -print
bash scripts/check-path-naming.sh
```

For each candidate file, report:

- Current path
- Proposed path
- Frontmatter presence
- `id` presence
- Whether the path is public or private

### 3. Find references

Search all relevant references before renaming:

```bash
rg -n "Old Path|old-file|\[\[old-note\]\]" . \
  -g '!local/.git/**' \
  -g '!**/.git/**'
```

Include:

- Markdown links and wiki-links
- `resources:` blocks in skill files
- shell scripts
- TypeScript extensions
- README/docs
- templates
- workflows

### 4. Produce a plan

Show:

```text
FILES TO MOVE/RENAME
  old -> new

REFERENCES TO UPDATE
  file:line old -> new

FRONTMATTER
  preserved ids:
  tags to add/update:

VALIDATION
  bash scripts/check-path-naming.sh
  bash scripts/privacy-scan.sh
  bash scripts/doctor.sh --summary

RISKS
  compatibility concerns:
  manual follow-ups:
```

Then ask for explicit confirmation.

### 5. Execute safely

After confirmation:

- Create parent directories.
- Use `git mv` when files are tracked.
- Use `mv` for untracked local files.
- Update references with exact replacements.
- Preserve all YAML frontmatter.
- If splitting/merging notes, keep original IDs only on the original logical note; create UUID5 IDs for new logical notes.

### 6. Self-heal this skill

If any changed path/reference appears in this skill:

- Update `system/skills/refactor-brain/SKILL.md` in the same refactor.
- Update this skill's `resources:` paths.
- Update examples and naming policy text.
- Re-read this skill after editing it to ensure the remaining instructions still match reality.

### 7. Validate

Run:

```bash
bash scripts/check-path-naming.sh
bash scripts/privacy-scan.sh
bash scripts/doctor.sh --summary
```

If `doctor.sh --summary` is too broad for the current slice, explain why and run the narrower relevant checks.

### 8. Report

Report:

- Files moved/renamed
- References updated
- New IDs generated
- Validation results
- Remaining warnings
- Suggested commit message

## Frontmatter requirements

New notes must include frontmatter following `System/Rules.md`.

Operational notes:

```yaml
---
date: YYYY-MM-DD
type: integration|security|preference|setup-history
tags: [tool, provider, domain]
status: active|deprecated|missing|needs-verification|experimental
last-confirmed: YYYY-MM-DD
confidence: high|medium|low
id: <UUID5>
---
```

Generate IDs with:

```bash
scripts/uuid5-gen.sh "path/to/note"
```

## Safety boundaries

- Do not move the live installed `agentBrain` checkout.
- Do not rename legacy public paths during onboarding.
- Do not overwrite `local/` content.
- Do not write secrets into public files.
- Ask before moving or saving company/internal/proprietary details.

## Example: local preference cleanup

Goal:

```text
Rename local/preferences/Tech Stack.md -> local/preferences/tech-stack.md
```

Plan:

```text
FILES TO RENAME
  local/preferences/Tech Stack.md -> local/preferences/tech-stack.md

REFERENCES TO UPDATE
  local/preferences/README.md:12 Tech Stack.md -> tech-stack.md

FRONTMATTER
  preserve id: abc...
  add tag: tech-stack if missing

VALIDATION
  check-path-naming
  privacy-scan
```

Only execute after confirmation.
