---
name: brain-extract
description: Move a project's full knowledge bundle (project doc + scoped learnings) from agentBrain vault into the project folder as a portable .brain-package/. Or bundle a whole space (--space) as a portable package stamped with its space-id. Default cascades vault originals to brain-forget (30d recoverable). Triggers — "extract project from brain", "bundle project knowledge", "brain-extract <slug>", "extract space", "bundle space".
---

# brain-extract — move project (or space) knowledge to a portable package

Extracts a project's vault content (per `.export-manifest.yml`) into
`<project>/.brain-package/` and cascades originals to brain-forget. With
`--space <slug>` it instead bundles the whole sealed space at `spaces/<slug>/`
(the space dir IS the scope — no manifest needed) and stamps the package with
the space's `space-id` as provenance.

## Invocation

```
brain-extract <slug> [--keep] [--to <path>] [--vault <path>]
brain-extract --space <slug> [--out <path>] [--vault <path>]
```

- `--space <slug>` — bundle every `.md` under `spaces/<slug>/`. Reads the stable
  `space-id` from `spaces/<slug>/index.md` (the "paspoort") and writes it into the
  package manifest as a top-level `space_id` field (also under `metadata`). Default
  disposition is `--keep` (no auto-forget for spaces in Phase 1).
- `--out <path>` — destination root for the `.brain-package/` (alias of `--to`).

## Status

Phase 1 MVP: happy-path only. No lockfile, no checkpoint, no rollback.
See `~/.agentBrain/vault/projects/brain-extract-restore/index.md` for full spec.

## Related

- [[brain-restore]] — inverse operation (restores spaces under `local/spaces/<slug>/`)
- [[brain-forget]] — cascade target
- [[brain-recall]] — recovery for trashed paths
