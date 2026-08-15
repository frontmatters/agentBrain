---
name: list-parks
description: List all parked agentBrain projects (status paused or blocked) with last-touched date and one-line status, so you can decide what to /unpark. Useful at the start of a new session ("what was I working on?") or as a discoverability layer over /park and /unpark. Triggers - "list-parks", "what parked work do I have", "show paused projects", "list parked projects", "what was I working on", "any backlog waiting".
related: [park, unpark, list-projects, relevant]
---

# list-parks — dashboard of parked work

`/list-parks` is the read-only sibling of [[park]] and [[unpark]]. It shows
what is parked, sorted by most recently touched, so you can decide what
(if anything) to resume.

## The simple rule of three

| Skill | When | Direction |
|---|---|---|
| `/list-parks` | **Start of a new session, or any time** | read — what is parked? |
| `/unpark <name>` or `/unpark <N>` | **You picked a project from /list-parks** | load — pick up the backlog |
| `/park` | **End of a working session, work isn't done** | save — checkpoint + insights |

Mnemonic: **see → load → save.**

## When to use

- Start of a new session — find out what is waiting before opening anything else.
- Mid-session orientation — "did I park anything related to this?"
- Before claiming a project is "fresh" — make sure there isn't already a
  parked version (avoid duplicating work or losing prior decisions).
- Cleanup pass — see which paused projects have gone stale (e.g. paused
  6+ months ago) and decide to either resume or mark `done`/`abandoned`.

## Do not use for

- Active discovery of *all* projects (use `ls ~/agentBrain/local/projects/`).
- Browsing learnings (use `grep` or `brain-search`).
- Reading the actual project content (just `Read` the index.md directly).

## Steps

### 1. Scan `local/projects/`

For every subdirectory:

- Read `index.md` (skip if missing — folder isn't a proper project).
- Extract from frontmatter: `status`, `priority`, `date`.
- Extract from body: first non-empty line of `## Status` paragraph (if any),
  or fall back to the first H1 title.

### 2. Filter

Include only projects whose `status` is `paused` or `blocked`. Exclude
`active`, `done`, or missing-status.

### 3. Sort

By `date:` descending (most recently touched first). Stable order within
the same date.

### 4. Render

Compact table with numbered rows:

```
#    PROJECT                       STATUS    PRIORITY  LAST TOUCHED  ONE-LINE
[1]  promote-demote-skill          paused    medium    2026-06-02    v1.1.1 done; 3 minor refinements open
[2]  foo-skill                     blocked   high      2026-05-30    awaiting external API access
[3]  bar-experiment                paused    low       2026-04-12    early-stage, deferred

Resume: /unpark <name>  OR  /unpark <number>  (numbers valid until next /list-parks)
```

If empty:

```
No parked work. (Either you have no paused/blocked projects, or
local/projects/ has no index.md files.)
```

### 4a. Cache the numbered index

After rendering, the bin script also writes a JSON index to
`~/agentBrain/local/.parks-index.json`:

```json
[{"n":1,"name":"promote-demote-skill","status":"paused","priority":"medium","date":"2026-06-02"}, ...]
```

This is consumed by `/unpark <N>` to resolve a number back to a project
name. The cache is overwritten on every `/list-parks` invocation, so
numbers are only valid until the next listing.

### 5. Suggest next action per row (optional)

For each row, the user can decide:

- `/unpark <N>` — pick this up now using its number from the table
- `/unpark <name>` — same, but resilient to a stale cache (numbers expire)
- `Read ~/agentBrain/local/projects/<name>/index.md` — inspect first
- Update status to `done` if it turned out not to need resuming
- Update status to `abandoned` if no longer relevant (rare)

Do not auto-act; `/list-parks` is read-only.

## Implementation notes

This is a small enough scan to do inline (a few `Read` + frontmatter
parsing). A `bin/list-parks` script is optional — see `bin/list-parks` if it exists
for a fast non-interactive listing.

For non-interactive use:

```bash
bash ~/agentBrain/system/skills/list-parks/bin/list-parks         # table to stdout
bash ~/agentBrain/system/skills/list-parks/bin/list-parks --json  # for tooling
```

## Anti-patterns (do not do)

- **Skipping /list-parks at session start.** Without it you may start fresh
  work on something you already parked — context loss.
- **Treating /list-parks as a to-do list.** It is a *parked-work view*, not a
  task tracker. Use `/journal` or a separate skill for tasks.
- **Listing every project.** Filter to paused/blocked; otherwise you can
  just `ls` the folder.

## Related

- [[park]] — save side of the loop
- [[unpark]] — load side of the loop
- [[project-update]] — underlying skill that creates/updates the index.md
  files this dashboard reads
