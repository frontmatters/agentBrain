---
date: 2026-06-04
type: system
tags: [skill, brain-forget]
id: e04ee007-fedb-5ac5-9a20-87fe30f10bdb
---

# brain-forget

Soft-delete an agentBrain note via the central trash.

## Purpose

Moves a note to `local/.trash/forget/<timestamp>/` so it disappears from `find`, `grep`, and listings without being permanently lost. Confirmation prompt by default; warns on backlinks.

## Usage

```
/brain-forget <path>
/brain-forget <path> --force
```

## Related

- [[brain-recall]] — restore a forgotten note from trash
- [[brain-hide]] — keep on disk but suppress from listings
