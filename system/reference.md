---
date: 2026-05-22
type: system
tags: [meta, reference]
id: 3763e854-b7e7-5303-84e8-eb38ba05a014
---

# Reference

Warm reference material moved out of `system/rules.md` so the hot per-session set
stays compact. Read these when the task calls for them; the essential boundary,
write-location routing, security, and how-to-write rules stay hot in
`system/rules.md`.

## Path naming policy

### Public layer (committed)

Public paths are **lowercase/kebab-case** (the historical Title Case names were
normalized). The public root folders:

```
system/    scripts/    templates/    docs/    tests/
learnings/  projects/  sessions/  daily-notes/  backlog/
user-preferences/  youtube-digest/
```

These names are **stable API** — do not rename. They are referenced by agents, scripts,
skills, and Obsidian configs. Renaming would break links and tooling.

For **new** public files and folders:

- Use **lowercase/kebab-case**
- Files: `my-new-note.md` not `My-New-Note.md`
- Folders: `new-folder/` not `New-Folder/`

### Private layer (`local/`)

All new `local/` content **must** use **lowercase/kebab-case**:

```
local/projects/my-project/
local/learnings/my-learning.md
local/research/electron-vs-tauri.md
local/sessions/archive/2026-05/20260518-143205-a7f3.md
```

Legacy mixed-case files in `local/` exist from before this policy. They are tracked
in `local/backlog/lowercase-local-path-migration.md` for future cleanup.

### Enforced by

- `scripts/check-path-naming.sh` — reports drift
- `scripts/doctor.sh` — includes naming audit
- `scripts/doctor.sh --strict` — fails on active local naming drift

## Maintenance routine

Run `/brain-review` monthly. Also run `/brain-insights` plus
`bash scripts/doctor.sh --summary` after major Pi or agentBrain updates. Before
public commits, run the privacy scan or doctor flow.

The review checks:

- Notes older than 6 months → mark as "needs refresh" (do not delete without review)
- `confidence: low` entries → confirmed 2x+? Upgrade to `high`. Still unconfirmed? Keep or retract
- Duplicates between patterns.md and troubleshooting.md → consolidate
- Entries without reproducible steps (troubleshooting) → add steps or retract
- `confidence: retracted` entries older than 3 months → archive or remove only after review

Use recoverable curation:

- Prefer dry-run/report first, mutation second
- Prefer consolidate or archive over delete
- Respect explicit keep/pin markers in notes or project files
- Treat note staleness as age + manual review unless local usage telemetry exists
- Keep archives under `local/` when they contain real user/project knowledge

## Path environment variables

agentBrain uses two canonical env vars for filesystem paths (prefer over hardcoded):

- **`AGENTBRAIN_DIR`** — brain checkout root. MUST contain `brain.json` + `system/` +
  `scripts/` + `local/` for validators to consider it healthy. Default:
  script-location-derived via `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`
  (logical `pwd`, NOT `pwd -P`, so symlinked `local/` is not resolved through).
  Override via `export AGENTBRAIN_DIR=/path/to/checkout`.
- **`AGENTBRAIN_HOME`** — install/config parent dir. Default `$HOME`. Used by
  install/setup scripts that write tool-configs OUTSIDE the checkout (`.bashrc`,
  `.claude/CLAUDE.md`, `.pi/agent/`, `~/.copilot/`, `~/.gemini/`,
  `~/.config/opencode/`). Convention: `AGENTBRAIN_DIR = $AGENTBRAIN_HOME/agentBrain`.

New consumer-facing code (skills, validators, doc-tools) should use `AGENTBRAIN_DIR`
for content access. `VAULT` (exported by `setup.sh`) and `ROOT_DIR` (script-local) are
legacy/implementation details — don't add new public usage.

## Forward-ref markers

A `[[target]]` to a note that doesn't exist yet (per the "link liberally" policy) MUST
be marked intentional, one of two ways:
- Prefix: `[[forward:target]]`
- Same-line comment: `[[target]] <!-- forward: <reason or planned-when> -->`

Unmarked unresolved wikilinks stay warnings; explicit forward-refs are silently
accepted by `check-local-content` (closes the "false-green by validator-relaxation" risk).

## Note format examples

### Troubleshooting entry

```markdown
## [Platform/Tool] — [Short description]

- **Problem**: what went wrong
- **Cause**: why
- **Solution**: exact fix
- **Context**: when this occurs
```

### Pattern entry

```markdown
## [Category]

- Pattern description — why it works
- Anti-pattern — why it does not work
```

## Related

- [[rules]]
- [[skills]]
