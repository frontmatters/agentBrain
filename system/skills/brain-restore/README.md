---
date: 2026-06-04
type: system
tags: [skill, brain-restore]
id: ab830750-3602-553f-a5df-205392f5f7f9
---

# brain-restore

Write a project's `.brain-package/` back into the agentBrain vault.

## Purpose

Reads `<package>/manifest.yml` and recreates notes at their original vault paths. Default KEEPS the package on disk as a persistent handover doc; asymmetric on purpose vs. brain-extract.

## Usage

```
brain-restore <package-path> [--move]
```

Use `--move` to delete the package after a successful restore.

## Related

- [[brain-extract]] — counterpart that creates the package
