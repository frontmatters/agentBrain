---
date: 2026-09-27
type: skill
tags: [skill, brand, workspace]
id: 98758f85-4d45-55c3-ad60-480d649de4c8
---

# Brand workspace

Use the [`brand-workspace` skill](SKILL.md) to inventory independent brand
workspaces, link a brand to technical renderer adapters, and plan migrations of
existing brand assets. Start with the read-only `status` step; moving or retiring
files requires explicit approval and a verified rollback plan.

The [`brand.json` template](templates/brand.json) records the brand identity,
its source of truth, and adapters. Unknown values stay `null` until verified.
This is a framework skill, not a separately published addon; its changes are
included in the framework release.
