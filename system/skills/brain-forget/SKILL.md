---
name: brain-forget
description: Soft-delete an agentBrain note to local/.trash/forget/. Default prompts for confirmation (--force to skip), shows backlinks pre-flight warning. Recoverable via /brain-recall. Triggers — "forget this", "soft-delete", "weggooien", "remove note".
---

# brain-forget — soft-delete a note via central trash

Moves a note to `local/.trash/forget/<timestamp>/`. Reversible via [[brain-recall]].

## When to use

- Truly obsolete (wrong assumption, abandoned tech choice).
- You want it out of `find`/`grep` results, not just listings.

## Invocation

```
/brain-forget <type>/<slug> [--file <name>] [--force] [--reason "<text>"]
```

Default: shows backlinks pre-flight warning + asks for confirmation. `--force` skips. `--reason "X"` records why.

For `projects/<slug>` (no `--file`): cascades — whole folder to trash.

## Cross-machine note

`.trash/` is gitignored. Forget is **local-only**. V2 will add tombstone-based sync.

## Related

- [[brain-recall]] — restore from trash
- [[brain-hide]] — non-destructive alternative
- [[brain-purge]] — make a forget permanent (empties trash batches)
- [[forward:brain-hide-forget]] — design spec
