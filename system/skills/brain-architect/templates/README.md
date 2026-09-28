---
date: 2026-08-07
type: system
tags: [skill, architecture, templates]
id: d58c92f5-cd1e-5a44-a1fd-d8fb5becc0ab
---

# brain-architect templates

Five fill-in skeletons, one per phase, assembled into a single dossier in
this order. Section anchors and field markers (`evidence:`,
`abort-condition:`, `⚠ Open`, `**Option N:**`, `**Recommendation:**`) are
fixed tokens the sibling `../scripts/validate.sh` greps for — never
translate or rename them; prose language is free (`--lang`).

| Template | Section it produces |
|---|---|
| `00-recon.md` | `## Recon` — map-first touchpoint table |
| `01-building-blocks.md` | `## Building Blocks` — mermaid mental model + component table |
| `02-constraints.md` | `## Constraints` — egress/zone diagram + six lenses |
| `03-decision.md` | one `### Decision:` record (repeat per question, under a hand-written `## Decisions`) |
| `04-open-questions.md` | `## Open Questions` — the ⚠ Open ledger |

Delete the instructional HTML comments and replace every `<angle-bracket>`
placeholder when filling them in; leftovers fail validation.
