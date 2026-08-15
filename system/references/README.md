---
date: 2026-08-08
type: system
tags: [system, references, dev-registry, spaces]
id: c3bc8d47-a1c2-58a3-9af9-6c6b150053ce
---

# system/references — shared reference mechanisms

Shared, path-agnostic mechanisms whose **private data lives in the mirror**
`local/references/`. This is the framework's mechanism/data split (`system/` =
HOW/WHERE, public · `local/` = WHAT, private) applied to reference tooling.

## dev-registry

Scans your dev checkouts and regenerates the registry table.

| Side | File | Role |
|---|---|---|
| **Mechanism** (here, committed) | `dev-registry.scan.sh` | the scanner (no personal paths) |
| **Mechanism** (here, committed) | `dev-registry.roots.example` | template you copy into `local/` |
| **Data** (`local/references/`, gitignored) | `dev-registry.roots` | YOUR search roots |
| **Data** (`local/references/`, gitignored) | `dev-registry.overrides` | manual `naam herkomst [status]` fixes |
| **Output** (`local/references/`, gitignored) | `dev-registry.md` | the generated table |

**Setup (once):**
```sh
cp system/references/dev-registry.roots.example local/references/dev-registry.roots
$EDITOR local/references/dev-registry.roots        # add your roots
```

**Refresh:**
```sh
bash "$AGENTBRAIN_DIR"/system/references/dev-registry.scan.sh
```

**Config precedence:** `$DEV_ROOTS` (colon list) → `$DEV_DIR` (single, back-compat)
→ `local/references/dev-registry.roots` → baked-in default `~/Developer`.

**Spaces integration (per-client tagging + canonical).** The scan reads
`local/.space-map.json` (built by `scripts/build-space-map.sh` from the space paspoorts).
Every checkout under a space's `code-root` gets a **Space** column, and the space's
`canonical` code-root is marked ✓ while its other code-roots show ⛔ decoy. This makes
"which checkout is the live one for this client?" a space-owned fact — set it once in
`local/spaces/<slug>/index.md` (`canonical:` field, see `docs/spaces.md`). Client checkouts
that live outside your roots (e.g. under `_work/`) are pulled in via their space code-roots,
so `dev-registry.roots` only needs your general dev area.

**Fallbacks** (for projects NOT in a space): a `status` third field in
`dev-registry.overrides` (`<name> <origin> canonical|decoy`), and an automatic `⚠ dup`
when one git origin appears under multiple roots.
