---
name: doctor
description: Run an agentBrain health audit. Use after framework changes, before publishing, or when the brain may be inconsistent.
argument-hint: Optional focus area (public, local, sessions, frontmatter)
user-invocable: true
resources:
  - scripts/brain.sh
  - scripts/checks/doctor.sh
  - system/rules.md
---

# Doctor

Run a health audit for agentBrain. There are two doctors:

- **`brain doctor`** checks this install: skill links, anchors, the vault and
  its notes, events, add-ons. It is what every installed release carries and
  what a user runs (`doctor.sh --user`).
- **`brain doctor --dev`** is the factory's gate for working on agentBrain
  itself: the framework's tests, negative cases, code and writing rules,
  shellcheck. It needs the agentBrain source; an installed release says so and
  points back to `brain doctor`.

## Steps

1. Run the doctor that fits:
   ```bash
   brain doctor          # an install: is it healthy?
   brain doctor --dev    # the agentBrain source: may this change ship?
   ```
   For release-quality work on the source, add `--pi-lens-strict` to the
   `--dev` run.
2. If a check fails, fix the root cause rather than suppressing the warning.
3. Re-run the same doctor until all checks pass.
4. Report:
   - Checks run
   - Issues found
   - Fixes applied
   - Remaining risks or recommendations

## Scope

`brain doctor` (install health):

- Version, anchors (brain.json, vault link, alias, git hooks)
- Skill links in every installed agent, and the paths agents are handed
- Add-on manifests on this machine
- The vault: note frontmatter and ids, wiki links (warn-only), learnings
  layout, project status, decisions, specs, preferences, spaces
- Event-bus data, the shared layer's secret gate, the private vault repo
- Onboarding state, shorthand (when enabled), Pi-lens findings (with Pi)

`brain doctor --dev` adds the factory's gates: privacy scan of the tracked
tree, README and frontmatter coverage of public docs, public wiki links, path
naming, code and writing rules, every test and negative case, bash syntax and
ShellCheck.

## Difference from `/brain-review`

- `/doctor` checks whether the agentBrain system is structurally healthy.
- `/brain-review` reviews the quality and freshness of knowledge content.
