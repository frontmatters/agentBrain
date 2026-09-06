---
date: 2026-05-18
type: integration
tags: [opensrc, tools, open-source, dependencies]
id: 778bb6ee-0be0-5323-8de5-417882f2b528
---

# opensrc

> Fetch source code for npm packages to give AI coding agents deeper context.  
> GitHub: <https://github.com/vercel-labs/opensrc>

`opensrc` fetches and caches the full source code of npm, PyPI, and crates.io packages
locally at `~/.opensrc/`. Agents can then `rg`, `cat`, and `find` in the real implementation
— not just types or docs.

## Install

```bash
# via bun (canonical — managed by scripts/configure-pi.sh)
bun add -g opensrc
```

> `scripts/configure-pi.sh` runs `ensure_opensrc` automatically — no manual install needed on a fresh machine.

## Core usage

```bash
# Read a file from the source
cat $(opensrc path zod)/src/types.ts

# Search across the source
rg "parseAsync" $(opensrc path zod)

# Works with any registry
opensrc path pypi:requests
opensrc path crates:serde
opensrc path facebook/react

# Auto-detects installed version from lockfile
opensrc path zod --cwd /path/to/project

# Multiple packages
opensrc path zod react @tanstack/query
```

`opensrc path` fetches on first use, then returns the cached path instantly.

## When to use it

Use `opensrc` when:

- You need to understand internal behavior that types don't reveal
- Debugging unexpected library behavior (e.g. why does `zod.parse` throw this?)
- Learning patterns from well-known implementations
- Verifying how a function handles edge cases internally

Don't use it for simple API usage — docs and types are enough for that.

## Pi skill

Available as `/skill:opensrc` in Pi.  
Source: `system/pi-config/skills/opensrc/SKILL.md`  
Symlinked to `~/.pi/agent/skills/opensrc` by `scripts/configure-pi.sh`.

## Cache management

```bash
opensrc list              # show cached packages
opensrc remove zod        # remove one
opensrc clean             # remove all
```

Cache lives at `~/.opensrc/` (override with `OPENSRC_HOME`).

## Bootstrap

`scripts/configure-pi.sh` installs the Pi skill symlink automatically.  
The `opensrc` binary itself must be installed separately (brew or npm — see above).
