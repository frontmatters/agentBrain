---
date: 2026-06-04
type: system
tags: [skill, brain-recall]
id: 6c5a6f6f-07ca-54c8-b559-1c9e00da28fe
---

# brain-recall

Restore a forgotten note from `local/.trash/forget/`.

## Purpose

Reverse of brain-forget. Resolves the target by trash timestamp, by `<type>/<slug>`, or by the number from `/list-hidden --include-trash`.

## Usage

```
/brain-recall <YYYYMMDD-HHMMSS>
/brain-recall <type>/<slug>
/brain-recall <N>
```

## Related

- [[brain-forget]] — counterpart that moves notes to trash
- [[list-hidden]] — `--include-trash` to enumerate forgotten batches
