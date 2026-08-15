---
date: 2026-08-14
type: system
tags: [skill, vault-review]
id: 1f6b38a2-d9d6-596f-af2b-2022ecb8524a
---

# vault-review

Broad periodic review of the agentBrain vault.

## Purpose

Wider than `brain-review` (which is structural + content quality). Covers:

- Vault-health check (notes per directory, missing frontmatter, `doctor.sh`)
- Wiki-link integrity (broken links, isolated notes)
- Pattern discovery (recurring problems/decisions/workarounds → learnings or the agent-guidance file)
- Agent-guidance sync check (CLAUDE.md / AGENTS.md / GEMINI.md vs the vault)
- Staleness (stale active notes, old low-confidence entries, aged backlog)
- Daily-notes review

Writes a report to `local/sessions/<YYYY-MM-DD>-vault-review.md`.

## Usage

```
/vault-review
```

Triggered manually; recommended every 2 weeks, minimum monthly.
