---
name: doctor
description: Run an agentBrain health audit. Use after framework changes, before publishing, or when the brain may be inconsistent.
argument-hint: Optional focus area (public, local, sessions, frontmatter)
user-invocable: true
resources:
  - scripts/doctor.sh
  - scripts/privacy-scan.sh
  - scripts/check-readmes.sh
  - scripts/check-frontmatter.sh
  - scripts/check-session-schema.sh
  - scripts/check-links.sh
  - scripts/check-path-naming.sh
  - scripts/check-agentbrain-local.sh
  - system/rules.md
---

# Doctor

Run a health audit for agentBrain itself.

## Steps

1. Run the automated doctor:
   ```bash
   bash scripts/doctor.sh
   ```
   Use stricter release-quality mode when preparing a 9.5+/10 release:
   ```bash
   bash scripts/doctor.sh --pi-lens-strict
   ```
2. If a check fails, fix the root cause rather than suppressing the warning.
3. Re-run `bash scripts/doctor.sh` until all checks pass.
4. Report:
   - Checks run
   - Issues found
   - Fixes applied
   - Remaining risks or recommendations

## Scope

The doctor checks:

- Public privacy scan
- README coverage for public markdown folders
- Frontmatter/schema hygiene
- Session continuity schema
- Unresolved Pi-lens worklog findings and review warnings (`--pi-lens-strict` fails on review warnings too)
- Semantic brain-review: stale, duplicate, misclassified notes
- Wiki-link target health
- Path naming drift (including lowercase/kebab-case audit)
- Private `local/` high-confidence secret scan
- Bash syntax for shell scripts
- ShellCheck when available

## Difference from `/brain-review`

- `/doctor` checks whether the agentBrain system is structurally healthy.
- `/brain-review` reviews the quality and freshness of knowledge content.
