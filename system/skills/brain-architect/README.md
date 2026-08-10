---
date: 2026-08-07
type: system
tags: [skill, architecture, analysis, validate]
id: fdcb9ef6-f0dd-51d7-9ca6-e5097dcd806f
---

# brain-architect

Evidence-gated architecture analysis of an existing system, executable by a
cheaper model. Five phases (recon → building blocks → six constraint lenses →
decision records → open-questions ledger), five fill-in templates with fixed
language-neutral tokens, and a deterministic `validate.sh` that gates
delivery on form: sections, evidence paths that must exist, two mermaid
diagrams, complete decision records, no placeholders.

## Quickstart

```
/brain-architect <repo-path> "design question" [--lang en|nl] [--html] [--peer-review]
```

The workflow and hard gates live in `SKILL.md`. The dossier lands in
`local/projects/<slug>/architecture` (vault) plus a frontmatter-free copy in
the target repo's `docs/architecture/`.

## Files

| File | Role |
|---|---|
| `SKILL.md` | Workflow, hard gates, delivery contract |
| `templates/00-04` | Fill-in skeletons per phase (see `templates/README.md`) |
| `scripts/validate.sh` | Deterministic form-checker (bash 3.2; exit 0 = deliverable) |
| `scripts/test-validate.sh` | 17-assertion fixture suite for the checker |

## Verify

```bash
bash scripts/test-validate.sh   # expects passed=17 failed=0
```
