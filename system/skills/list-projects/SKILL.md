---
name: list-projects
description: List ALL agentBrain projects in local/projects/ with status, priority, date, and one-line description. The general project catalog — broader view than /list-parks (which filters to paused/blocked). Read-only. Useful for "what projects do I have?", finding a stale or unstatus-ed project, or audit. Triggers - "list-projects", "list all projects", "show projects", "project catalog", "what projects exist", "show active projects".
related: [project-update, list-parks]
---

# list-projects — full catalog of agentBrain projects

`/list-projects` is the general-purpose read-only view over
`local/projects/`. Sibling of [[list-parks]] but unfiltered by status; the
broader catalog.

## Relationship to /list-parks

| Skill | Filter | Use when |
|---|---|---|
| `/list-projects` | none by default; filterable via `--status` | "what projects do I have?" or audit |
| `/list-parks` | `status: paused` or `blocked` only | "what should I /unpark?" — park-loop dashboard |

`/list-parks` is effectively `/list-projects --status paused,blocked` with a
park-loop-specific framing. Both exist because they answer different
questions.

## When to use

- **Catalog browsing**: "what projects exist in this brain?"
- **Audit**: spot projects without a `status:` field, or stale entries.
- **Pre-/park check**: before parking a new project, confirm no existing
  project covers the same scope.
- **Status review**: see distribution of active/paused/blocked/done.

## Do not use for

- Park-loop dashboard (use [[list-parks]] — it filters automatically).
- Reading project content (`Read` the index.md directly).
- Creating/updating projects (use [[project-update]]).

## Steps

### 1. Scan `local/projects/`

For every subdirectory with an `index.md`:

- Read frontmatter for: `status`, `priority`, `date`, `name`.
- Extract from body: first non-empty line of `## Status` paragraph, or
  fall back to first non-empty line of `## Goal`.

### 2. Filter (optional)

- `--status <s>` — comma-separated list: `active`, `paused`, `blocked`,
  `done`, `abandoned`, `none` (missing status field). Default: all.
- `--priority <p>` — comma-separated: `high`, `medium`, `low`.
- `--since YYYY-MM-DD` — only projects modified on or after.
- `--tag <name>` — filter by tag.

### 3. Sort

By `date:` descending. Stable order within same date.

### 4. Render

Compact table:

```
PROJECT                  STATUS   PRIORITY  LAST TOUCHED  ONE-LINE
park-system              paused   medium    2026-06-03    Three-skill bundle for session-handover
promote-demote-skill     paused   medium    2026-06-02    v1.1.1 done; 3 minor refinements open
foo-bar-thing            done     low       2026-04-12    Closed; migrated to system/
```

### 5. Suggest next actions

- `Read ~/agentBrain/local/projects/<name>/index.md` — inspect
- `/unpark <name>` if status=paused/blocked
- `/project-update` if status is missing or stale

## Implementation

`bin/list-projects` script available:

```bash
bash ~/agentBrain/system/skills/list-projects/bin/list-projects
bash ~/agentBrain/system/skills/list-projects/bin/list-projects --status active,paused
bash ~/agentBrain/system/skills/list-projects/bin/list-projects --priority high
bash ~/agentBrain/system/skills/list-projects/bin/list-projects --since 2026-06-01
bash ~/agentBrain/system/skills/list-projects/bin/list-projects --json
```

## Anti-patterns (do not do)

- **Using /list-projects when /list-parks applies.** The park-loop has a
  specific use case; using the broader view forces you to mentally filter.
- **Treating /list-projects as task tracker.** Tasks live elsewhere (in
  individual project indexes' Backlog sections).
- **Skipping the `status:` field** when creating a project — it leaves
  the project as `none` in /list-projects, which makes filtering useless.

## Related

- [[list-parks]] — focused sibling, paused/blocked only
- [[project-update]] — counterpart; creates/updates the index.md files
  this dashboard reads
- [[list-learnings]] — sibling dashboard but for learnings, not projects
