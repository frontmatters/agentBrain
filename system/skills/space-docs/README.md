---
date: 2026-08-09
type: system
tags: [skill, docs, self-contained, transferable, validate]
id: cf008a96-9bb7-55e9-a120-057b6430e074
---

# space-docs

Produce a **self-contained, transferable documentation set** for a project or
"space" — a standalone docs bundle (README + ARCHITECTURE + ROADMAP + MEMORY,
with rendered diagrams) that stands on its own boundary and can be handed to a
colleague or moved to another machine unchanged.

- **SKILL.md** — the workflow (scope → scaffold → fill self-contained → render
  diagrams → validate boundary → publish).
- **scripts/validate.sh** — deterministic boundary check: FAILs on machine-local
  paths, private/vault references, and dead/absolute internal links; WARNs on
  in-scope internal hosts. Exit 0 = self-contained.
- **scripts/test-validate.sh** — asserts the validator passes a clean bundle and
  fails a leaky one.
- **templates/** — the doc-set skeletons.

## The boundary rule

Everything the docs reference lives inside the space's own boundary (the docs
repo, or the project's own repos/infra/code). Nothing points out — no
machine-local paths, no private notes/vault, no dead links. If it points out,
rewrite it in or drop it.

## Origin

Distilled (2026-08-09) from making a real project's ensemble docs fully
self-contained + transferable — a by-hand boundary audit turned into a
repeatable gate. Related: [[brain-architect]].
