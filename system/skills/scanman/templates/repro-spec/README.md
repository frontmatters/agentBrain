---
date: 2026-06-01
type: system
tags: [skill, scanman, templates, repro-spec]
id: 1199ea81-1099-56c2-bd83-2f98db038842
---

# Repro-spec templates

Template schemas used by `scanman --mode=reproduction-spec` for per-archetype distillation.

| Template | Archetype |
|----------|-----------|
| `primitive.md` | Base shape; all archetypes inherit |
| `data-only.md` | Pure data structures, no behavior |
| `host-export.md` | Modules that expose state to a host runtime |
| `state-machine.md` | Stateful modules with explicit transitions |

Templates contain placeholders (`<...>`, `{{...}}`) — they are not vault notes and are exempt from the standard frontmatter schema. See `../../SKILL.md` for the full workflow and `../../SCANMAN_REPRO_SPEC_PLAYBOOK.md` for the per-archetype execution playbook.
