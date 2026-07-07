---
name: brain-restore
description: Restore a project's knowledge bundle from a .brain-package/ back into the agentBrain vault. Space packages (carrying a space_id) are restored under local/spaces/<slug>/ only. Default keeps the package as persistent handover. Triggers — "restore project to brain", "brain-restore <package>", "import knowledge bundle", "restore space".
---

# brain-restore — write project (or space) knowledge back to the vault

Reads `<package>/manifest.yml` and writes notes back to their original
vault paths. A space package (one whose manifest carries a top-level
`space_id`) is restored under `local/spaces/<slug>/` only — restore refuses to
write a space note anywhere outside `spaces/<slug>/` and rejects unsafe slugs
(those containing `/` or `..`).

## Invocation

```
brain-restore <package-path> [--move] [--space] [--vault <path>]
```

- `--space` — require the package to be a space package (carrying `space_id`).
  Space packages are auto-detected from the manifest even without this flag;
  `--space` makes the expectation explicit and errors on a non-space package.
- `--move` — remove the package after a successful restore.

Notes are matched to their target by frontmatter `id` (or the UUID5 of the
target's vault-relative path when the target does not yet exist).

## Status

Phase 1 MVP: happy-path only. Default overwrite + warn on collision.
See `~/.agentBrain/vault/projects/brain-extract-restore/index.md` for full spec.

## Related

- [[brain-extract]] — inverse operation
