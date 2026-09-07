---
date: 2026-05-18
type: system
tags: [skill, brain-review]
id: 6c06a646-9a22-5e83-affc-3724ab1ca31c
---

# brain-review

Monthly review skill for agentBrain maintenance.

## Purpose

Scans all notes for:

- Notes older than 6 months → mark as "needs refresh"
- `confidence: low` entries → upgrade or retract
- Duplicates → consolidate
- Troubleshooting entries without reproducible steps → add or retract
- `confidence: retracted` entries older than 3 months → safe to remove
- Session archive health (structure, broken links, unusually large archives)

## Usage

```
/brain-review
```

Triggered manually, recommended monthly.
