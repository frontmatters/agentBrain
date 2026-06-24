---
name: brain-restore
description: Restore a project's knowledge bundle from a .brain-package/ back into the agentBrain vault. Default keeps the package as persistent handover. Triggers — "restore project to brain", "brain-restore <package>", "import knowledge bundle".
---

# brain-restore — write project knowledge back to vault

Reads `<package>/manifest.yml` and writes notes back to their original
vault paths.

## Invocation

```
brain-restore <package-path> [--move]
```

## Status

Phase 1 MVP: happy-path only. Default overwrite + warn on collision.
See `~/.agentBrain/vault/projects/brain-extract-restore/index.md` for full spec.

## Related

- [[brain-extract]] — inverse operation
