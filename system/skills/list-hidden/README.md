---
date: 2026-06-04
type: system
tags: [skill, list-hidden]
id: cbd50b7a-7b93-5769-a53b-01feaa75f7a0
---

# list-hidden

Dashboard of hidden (and optionally forgotten) agentBrain notes.

## Purpose

Read-only view that enumerates notes carrying `hidden: true`, plus — with `--include-trash` — forgotten batches in `local/.trash/forget/`. Each row is numbered so `/brain-unhide <N>` and `/brain-recall <N>` can resolve by index.

## Usage

```
/list-hidden
/list-hidden --include-trash
```

## Related

- [[brain-hide]] / [[brain-unhide]] — manage hidden flag
- [[brain-forget]] / [[brain-recall]] — manage trash
