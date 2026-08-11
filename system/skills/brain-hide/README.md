---
date: 2026-06-04
type: system
tags: [skill, brain-hide]
id: c7f5fe73-d0aa-532e-90f6-9d0c1fd274b3
---

# brain-hide

Hide a note from `/list-*` output without deleting it.

## Purpose

Adds `hidden: true` and `hidden-at:` to the note's frontmatter. The file stays in place — only listing skills filter it out. Use for archival items that no longer need to surface daily.

## Usage

```
/brain-hide <type>/<slug>
```

## Related

- [[brain-unhide]] — clear the hidden flag
- [[list-hidden]] — see what is currently hidden
