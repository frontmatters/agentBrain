---
date: 2026-06-04
type: system
tags: [skill, brain-extract]
id: 8e3ec34b-4f7b-57ec-a3ce-77b4a7415372
---

# brain-extract

Move a project's full knowledge bundle from the agentBrain vault into the project folder.

## Purpose

Bundles a project's index plus scoped learnings into a portable `.brain-package/` inside the target project, then cascades the vault originals to brain-forget (recoverable 30d). The package becomes the project's persistent knowledge contract.

## Usage

```
brain-extract <slug> [--keep] [--to <path>]
```

Defaults to MOVE. Use `--keep` when you want the vault copy to remain.

## Related

- [[brain-restore]] — reverse direction (package back into vault)
- [[brain-forget]] — trash where originals cascade
