---
name: brain-extract
description: Move a project's full knowledge bundle (project doc + scoped learnings) from agentBrain vault into the project folder as a portable .brain-package/. Default cascades vault originals to brain-forget (30d recoverable). Triggers — "extract project from brain", "bundle project knowledge", "brain-extract <slug>".
---

# brain-extract — move project knowledge to project folder

Extracts a project's vault content (per `.export-manifest.yml`) into
`<project>/.brain-package/` and cascades originals to brain-forget.

## Invocation

```
brain-extract <slug> [--keep] [--to <path>] [--raw|--no-redact|...]
```

## Status

Phase 1 MVP: happy-path only. No lockfile, no checkpoint, no rollback.
See `~/.agentBrain/vault/projects/brain-extract-restore/index.md` for full spec.

## Related

- [[brain-restore]] — inverse operation
- [[brain-forget]] — cascade target
- [[brain-recall]] — recovery for trashed paths
