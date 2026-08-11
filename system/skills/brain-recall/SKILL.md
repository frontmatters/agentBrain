---
name: brain-recall
description: Restore a forgotten agentBrain note from local/.trash/forget/. Resolves by timestamp, slug, or number. Triggers — "recall", "undo forget", "restore note", "haal terug uit trash".
---

# brain-recall — restore a forgotten note

Counterpart to [[brain-forget]].

## Invocation

```
/brain-recall <YYYYMMDD-HHMMSS>            # by trash batch timestamp
/brain-recall <type>/<slug>                # search all batches
/brain-recall <N>                          # number from /list-hidden --include-trash
```

## Conflict resolution

If target original path now has a file:

```
brain-recall: conflict at local/learnings/foo.md — target already exists.
  Use: /brain-forget learnings/foo && /brain-recall <TS>
```

Refuses with exit 2 — pick explicitly.

## Related

- [[brain-forget]] — counterpart
- [[list-hidden]] — see what is in trash
- [[forward:brain-hide-forget]] — design spec
