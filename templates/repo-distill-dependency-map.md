# 00b Dependency Map

## Related
- `index.md`
- `00-file-inventory.md`
- `01-system-map.md`
- `02-runtime-model.md`

## Purpose
Make code-level and package-level dependencies explicit.

## Coverage Link
- Source inventory: `00-file-inventory.md`
- Analysis status: bootstrap / manually enriched / verified
- Files/areas used for this dependency map:
- Major deferred areas affecting this map:

## Package Dependency Overview
| Package/Module | Direct Depends On | Runtime Role | Risk Notes |
|---|---|---|---|
| | | | |

## Import/Relation Hotspots
List the files/modules that appear central by imports, exports, or references.

## Package-Level Dependency Graph
```text
package-a
  -> package-b
  -> package-c
package-c
  -> external-lib-x
```

## File/Module Import Graph
Use selective graphs for architecturally important files only.

```text
entry.ts
  -> runtime.ts
  -> state/store.ts
runtime.ts
  -> effects.ts
  -> replay.ts
effects.ts
  -> shell.ts
```

Legend:
- `A -> B` = import / dependency / call edge
- `A => B` = writes / generates
- `A ~> B` = runtime data/event flow

## External Dependencies
| Dependency | Where Used | Why It Exists | Replaceable? | Notes |
|---|---|---|---|---|
| | | | | |

## Central Hubs
- Files/modules that most architectural paths seem to pass through
- Why they are central
- Which redesign decisions they influence

## Internal Coupling Notes
- Which files are central hubs?
- Which modules are thin wrappers?
- Which modules are dangerously over-coupled?
- Which dependencies are architectural vs incidental?

## Confidence
- Coverage level for this dependency map:
- Highest-confidence dependency areas:
- Lowest-confidence dependency areas:
- Bootstrap-only claims still present:
- Manual verification still needed for:
