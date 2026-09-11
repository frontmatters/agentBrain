---
date: 2026-09-11
type: system
tags: [skill, rnd-init, scaffold, artefacts, convention, agentbrain]
id: aea8997d-d105-55ce-8178-40639763453d
---

# rnd-init

> Scaffolds the `R&D/` convention in a repository: one kept-forever place for
> the artefacts a project produces while proving itself.

## Files

| File | Role |
| --- | --- |
| `SKILL.md` | When to reach for it, and what each option means. |
| `bin/rnd-init` | The scaffold. Idempotent, with a `--dry-run`. |
| `test.sh` | The invariants: nothing is overwritten, a second run is a no-op, git-ignored folders stay out of the commit, and the legacy migration moves data rather than deleting it. |

The convention itself travels inside the generated `R&D/README.md`, so a repo
that has been scaffolded needs nothing further from this skill.
