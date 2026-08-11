# 02 Runtime Model

## Related
- `index.md`
- `00b-dependency-map.md`
- `01-system-map.md`
- `03-core-primitives.md`
- `05-redesign-v1.md`

## Purpose
Reconstruct how the system behaves over time.

## Coverage Link
- Source inventory: `00-file-inventory.md`
- Analysis status: bootstrap / manually enriched / verified
- Claim discipline: verified-only main path / mixed / bootstrap
- Files/areas used for this runtime model:
- Major deferred areas affecting this model:

## Main Flow
1. Startup
2. Configuration/load
3. Execution loop
4. Pause/approval/gating
5. Persistence
6. Resume/replay/exit

Write the actual repo-specific flow here. If a step is inferred rather than verified, label it. For strict scans, keep the main path verified-only and move uncertainty into separate inferred/unknown notes.

## Control Flow
- What starts a run/session?
- What decides the next step?
- What can interrupt flow?
- What completes or aborts flow?

## Data Flow
- Inputs
- Internal state transitions
- Outputs/artifacts
- External calls/providers

## Data Flow Charts
### High-level Flow
```text
User/Input
  -> Entry point
  -> Runtime/Coordinator
  -> State/Journal
  -> Effects/Tasks
  -> Outputs
```

### Detailed Flow
```text
[input] -> [parser] -> [planner] -> [executor]
                      -> [state store]
executor -> [artifacts/logs]
executor -> [external provider]
```

## Main Functions / Methods and Usage
| Function / Method | Location | Claim Level | Role in Flow | How It Is Used |
|---|---|---|---|---|
| | | | | |

## Pseudocode Reconstruction
### Verified Main Runtime Path
```text
[startup] -> [main coordinator] -> [core helpers/adapters] -> [outputs]
```

### Inferred / Secondary Paths
```text
[input/event] -> [handler] -> [state change] -> [side effect]
```

### Unknown / Not Yet Proven
- 

Capture only the architecturally important flows. Prefer a small number of accurate reconstructions over fake completeness.

## State Transitions
| State | Trigger In | Trigger Out | Persisted? | Notes |
|---|---|---|---|---|
| | | | | |

## Persistence Model
- What is written to disk
- When writes happen
- Resume/recovery behavior
- Replay behavior if any

## Trust Boundaries
- User input
- Repo/workspace input
- Network/model/provider input
- Tool/shell/plugin input

## Open Questions
- Runtime ambiguities
- Paths not yet verified
- Which claims were intentionally left `unknown` pending deeper source review?

## Confidence
- Coverage level for this runtime reconstruction:
- Highest-confidence paths:
- Lowest-confidence paths:
- Verified claims included in main path:
- Inferred claims still present:
- Unknown / not yet proven areas:
- Bootstrap-only claims still present:
- Manual verification still needed for:
