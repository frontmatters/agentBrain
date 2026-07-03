---
date: 2026-06-11
type: system
tags: [skill, brain-purge]
id: edffcdb6-91fa-5b34-beab-0b701ab263f5
---

# brain-purge

Permanently delete forget-batches from the central trash.

## Purpose

Counterpart that makes `/brain-forget` final: removes `local/.trash/forget/<timestamp>/` from disk. Always runs as a preview first (validation + exact listing of what disappears); deletion requires restating the batch-id via `--confirm`. No `--force` exists by design.

## Usage

```
/brain-purge <batch-id>                        # preview
/brain-purge <batch-id> --confirm <batch-id>   # permanent delete
/brain-purge all --confirm ALL                 # empty the trash
```

## Related

- [[brain-forget]] — soft-delete a note to the trash
- [[brain-recall]] — restore from trash (impossible after purge)
