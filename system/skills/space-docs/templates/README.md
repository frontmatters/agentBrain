---
date: 2026-08-09
type: system
tags: [skill, docs, templates]
id: 3462cdc2-85a9-53db-adae-4c74ad6ae0a6
---

# space-docs templates

Skeletons for a self-contained docs bundle. Copy into the target docs folder,
rename to the plain output names, and replace every `<placeholder>`.

| Template | Copy to | Purpose |
|---|---|---|
| `01-readme.md` | `README.md` | the map / entry point |
| `02-architecture.md` | `ARCHITECTURE.md` | system, boundary, ADRs, open questions |
| `03-roadmap.md` | `ROADMAP.md` | milestones + building blocks |
| `04-memory.md` | `MEMORY.md` | footprint per component (measure it) |

Drop any that do not apply; add space-specific docs as needed. Keep all
references portable and inside the boundary — `scripts/validate.sh` gates it.
Render Mermaid diagrams to PNG (`mmdc -i x.mmd -o x.png -t neutral -b white -s 2`)
and keep the `.mmd` sources in `assets/`.
