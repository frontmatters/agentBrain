# 01 System Map

## Related
- `index.md`
- `00-file-inventory.md`
- `00b-dependency-map.md`
- `02-runtime-model.md`
- `03-core-primitives.md`

## Purpose
Describe the system at rest: what exists, where it lives, and what each major part is responsible for.

## Coverage Link
- Source inventory: `00-file-inventory.md`
- Analysis status: bootstrap / manually enriched / verified
- Files/areas used for this map:
- Major deferred areas affecting this map:

## Repo Shape
- Root packages/modules
- Important directories
- Build/runtime boundaries

## Repo Tree
```text
repo/
├─ package-a/
├─ package-b/
└─ docs/
```

Keep it selective: show only architecturally relevant paths.

## Major Components
| Component | Path | Type | Responsibility | Evidence | Notes |
|---|---|---|---|---|---|
| | | | | | |

## File/Module Relationship Graph
```text
<repo root>
├─ component-a
│  └─ depends on -> component-b
└─ component-c
```

Use arrows like:
- `A -> B` = imports/calls/depends on
- `A => B` = generates/writes
- `A ~> B` = runtime/event/data flow

## Entrypoints
- CLI entrypoints
- Server entrypoints
- Library entrypoints
- Plugin/extension entrypoints

## State and Storage
- Runtime state dirs
- Config files
- Cache dirs
- Journals/logs/artifacts

## External Surfaces
- Commands
- APIs
- Hooks
- Plugins/extensions
- MCP/tools if relevant

## Dependency Notes
- Direct dependencies that matter architecturally
- Optional/runtime-only dependencies

## Open Questions
- Unknown component roles
- Areas needing deeper runtime tracing
- Which component responsibilities are still bootstrap-inferred rather than verified from source?
