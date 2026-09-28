---
date: 2026-09-11
type: system
tags: [skill, project-init, scaffold, identity, convention, agentbrain]
id: e133ab2a-ecda-546d-9186-0e5fc43ec323
---

# project-init

> Applies the owner's project-type decisions to a repository: repository-local
> git identity, the LICENSE holder for that type, and the R&D scaffold.

## Files

| File | Role |
| --- | --- |
| `SKILL.md` | When to reach for it, and how to define the types. |
| `bin/project-init` | The mechanism. Ships with no brands in it. |
| `test.sh` | The invariants: the global git identity is never touched, an incomplete type is skipped rather than half applied, a LICENSE is never rewritten, and a machine with no types still works. |

The types live in the owner's vault, never here. See `SKILL.md` for the schema
and `templates/local-starters/` for the seeded example.
