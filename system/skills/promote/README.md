---
date: 2026-06-04
type: system
tags: [skill, promote]
id: af588f35-f72e-5d45-a553-a04247fdf444
---

# promote / demote

Move artifacts between mirror folders `local/X/` and `system/X/`.

## Purpose

Path-swap across the five canonical mirror folders (`addons`, `agent-config`, `integrations`, `pi-config`, `skills`). Promote when graduating an experimental artifact to the canonical framework; demote when pulling one back to private experimentation.

## Usage

```
/promote <relative-path>
/demote <relative-path>
```

See `SPEC.md` for the full design.

## Related

- system/skills/_shared — promotion targets for skill helpers
