---
name: list-hidden
description: Dashboard of hidden and (optionally) forgotten agentBrain notes. Numbered table for resolution by /brain-unhide <N> and /brain-recall <N>. Triggers — "list-hidden", "show hidden", "what did I hide", "what's in trash".
---

# list-hidden — see what is hidden or forgotten

Read-only.

## Invocation

```
/list-hidden                    # hidden notes only
/list-hidden --include-trash    # also show forgotten batches
```

## Output

```
#    TYPE         PATH
[1]  learnings    local/learnings/Foo.md
[2]  projects     local/projects/bar/index.md

#    BATCH               ORIGINAL PATHS    (with --include-trash)
[3]  20260603-153012     local/learnings/Old.md
```

Single counter across hidden + trashed. Use `/brain-unhide <N>` for hidden, `/brain-recall <N>` for trashed.

## Cache

Writes `~/agentBrain/local/.hidden-index.json` for `<N>` resolution. Overwrites on every run.

## Related

- [[brain-hide]] / [[brain-unhide]]
- [[brain-forget]] / [[brain-recall]]
- [[list-parks]] — analogous pattern
- [[forward:brain-hide-forget]] — design spec
