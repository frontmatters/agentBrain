---
date: YYYY-MM-DD
type: research
tags: [repo-distill, architecture, analysis]
status: active
id: <UUID5>
repo: <repo-name>
source: session
---

# Repo Distill — <repo-name>

## Goal
- What repo is being analyzed
- Why it is being analyzed
- What target system/use case the distillation serves

## Scope
- In scope packages/modules
- Out of scope packages/modules
- Analysis depth target

## Inputs
- Repo URL/path
- Version/ref/commit analyzed
- Related notes/docs
- Scanman method version

## Outputs
- [ ] 00-file-inventory.md
- [ ] 00b-dependency-map.md
- [ ] 01-system-map.md
- [ ] 02-runtime-model.md
- [ ] 03-core-primitives.md
- [ ] 04-risk-and-bloat.md
- [ ] 05-redesign-v1.md

## Output Status
| File | Exists | Bootstrap Generated | Manually Enriched | Verified Enough For Current Conclusions | Notes |
|---|---|---|---|---|---|
| `00-file-inventory.md` | no | no | no | no | |
| `00b-dependency-map.md` | no | no | no | no | |
| `01-system-map.md` | no | no | no | no | |
| `02-runtime-model.md` | no | no | no | no | |
| `03-core-primitives.md` | no | no | no | no | |
| `04-risk-and-bloat.md` | no | no | no | no | |
| `05-redesign-v1.md` | no | no | no | no | |

## Detected Stack
- Languages
- Frameworks / tooling
- Entrypoint candidates
- Context assist notes

## Context7 Assist

**For the calling agent**: if you have access to context7 (or an equivalent local-docs source — Devbox, vendored package docs, etc.), and the Detected Stack lists frameworks you can look up, populate this section with 2-4 canonical-docs snippets per detected framework before enriching `02-runtime-model.md` and `03-core-primitives.md`. Grounding later claims in canonical docs prevents memory-based drift.

This section is intentionally agent-agnostic: bash `scanman scan` does not invoke context7 itself (Claude-specific MCP). The hook is the section header — any agent runtime fills the body.

- _no context7-assist findings yet — populate when running with context7-capable agent_

## Coverage
- Inventory source: `00-file-inventory.md`
- Coverage status: sampled / selective / focused / broad / near-exhaustive
- Operating mode target: bootstrap / strict-runtime / strict-distill / complete
- Bootstrap status: not started / bootstrap generated / manually enriched / verified enough for current conclusions
- Major deferred areas:

## Key Questions
- What is the actual engine?
- Which primitives are essential?
- What is replaceable or unnecessary?
- What should the improved target design look like?

## Status
- Current phase
- Known blockers
- Next action
- Completion state: bootstrap only / runtime verified / distillation incomplete / complete enough for purpose
- Enrichment rule: update the canonical docs in this folder; avoid creating sibling pass folders unless preserving a meaningful before/after snapshot

## Related
- `00-file-inventory.md`
- `00b-dependency-map.md`
- `01-system-map.md`
- `02-runtime-model.md`
- `03-core-primitives.md`
- `04-risk-and-bloat.md`
- `05-redesign-v1.md`
