---
name: brain-unhide
description: Restore a hidden agentBrain note to listings. Removes `hidden:` + `hidden-at` from frontmatter. Counterpart to /brain-hide. Triggers — "unhide", "bring back", "restore from hidden", "make visible again".
---

# brain-unhide — clear hidden flag from a note

Counterpart to [[brain-hide]]. Removes the `hidden:` and `hidden-at:` lines from a note's frontmatter so listings find it again.

## Invocation

```
/brain-unhide <type>/<slug> [--file <name>]
/brain-unhide <N>                              # number from /list-hidden output
```

Number resolution uses `~/agentBrain/local/.hidden-index.json` (written by `/list-hidden`).

## Related

- [[brain-hide]] — counterpart
- [[list-hidden]] — see what is hidden
- [[brain-recall]] — for forgotten (trashed) notes
- [[forward:brain-hide-forget]] — design spec
