---
name: list-learnings
description: List recent learnings stored in local/learnings/ with date, tags, and title, so you can review what you have captured lately or find a relevant insight by topic. Read-only knowledge-base view. Useful for knowledge-review at the end of a project, pattern-spotting across recent sessions, or quickly finding a learning you remember writing but cannot place. Triggers - "list-learnings", "show recent learnings", "what have I learned recently", "list my insights", "knowledge review", "list learnings by tag".
related: [save-learning]
---

# list-learnings — dashboard of captured learnings

`/list-learnings` is the read-only knowledge-base sibling of [[save-learning]].
It lists what you have captured, sorted by most recently created, so you
can review or rediscover insights without grepping the vault.

Where [[list-parks]] shows project **state** (paused/blocked work), `/list-learnings`
shows knowledge **distillation** (what you have learned across all projects).

## When to use

- **End of project review**: what insights came out of the work just
  finished?
- **Knowledge audit** (monthly-ish): scan recent learnings for patterns
  that should escalate to CLAUDE.md or system/rules.md.
- **Pattern-spotting**: "didn't I write something about bash portability
  last week?" — find it without remembering the exact slug.
- **Onboarding a new session topic**: glance at recent tags to see
  what's been on your mind.

## Do not use for

- Reading a learning's content (just `Read` the file directly).
- Saving a new learning (use [[save-learning]]).
- Project state (that's [[list-parks]]).
- Full-text search (use `brain-search` or `grep`).

## Steps

### 1. Scan `local/learnings/`

For every `*.md` file (excluding `extracted/` subfolder):

- Read frontmatter for: `date`, `tags`, `confidence`.
- Extract H1 title from the body.
- Skip files without proper learning frontmatter (`type: learning`).

### 2. Filter (optional flags)

- `--tag <name>` — show only learnings whose tags include `<name>`.
- `--recent <N>` — show only the N most recent (default: 20).
- `--since YYYY-MM-DD` — show only learnings on or after this date.
- `--space <slug>` — opt-in view of a single space's own learnings
  (`local/spaces/<slug>/learnings`) instead of the default view. Space
  content is never surfaced unless you ask for it with `--space`.

### 3. Sort

By `date:` descending (most recent first). Stable order within the same
date.

### 4. Render

Compact table:

```
DATE        TAGS                              TITLE
2026-06-02  peer-review, llm, process         LLM peer-review: value is in 2-3 hits
2026-06-02  bash, bash-3.2, macos             Bash 3.2 has no associative arrays
2026-05-30  agentbrain, design-rule           agentBrain artifacts must be agent-agnostic
```

### 5. Suggest next actions

After the table, useful next steps:

- `Read ~/agentBrain/local/learnings/<slug>.md` — inspect a learning
- Look for patterns: 3+ learnings on the same topic may warrant promotion
  to `system/rules.md` or `CLAUDE.md`
- Cross-check connectivity: any learning with no incoming wiki-links is
  an orphan — link it from a project or related learning

## Implementation notes

A `bin/list-learnings` script is available for fast non-interactive listing:

```bash
bash ~/agentBrain/system/skills/list-learnings/bin/list-learnings                   # table, last 20
bash ~/agentBrain/system/skills/list-learnings/bin/list-learnings --recent 50       # last 50
bash ~/agentBrain/system/skills/list-learnings/bin/list-learnings --tag bash        # filter by tag
bash ~/agentBrain/system/skills/list-learnings/bin/list-learnings --since 2026-06-01
bash ~/agentBrain/system/skills/list-learnings/bin/list-learnings --space <slug>    # opt-in: a space's own learnings
bash ~/agentBrain/system/skills/list-learnings/bin/list-learnings --json            # machine-readable
```

The default view globs `local/learnings/*.md` only, so space content
(`local/spaces/<slug>/learnings/`) never appears unless `--space <slug>` is
passed. The slug is validated (no `/`, `..`, empty, or leading dot) to prevent
path escape.

## Anti-patterns (do not do)

- **Using /list-learnings to dump everything.** Always filter with `--tag` or
  `--recent` when the vault grows. Wall-of-text is no better than no
  view at all.
- **Treating /list-learnings as authority.** A learning is a captured
  insight, not a rule. If a learning has converged into a rule, escalate
  it to `system/rules.md` or `CLAUDE.md`.
- **Skipping /list-learnings at end-of-session.** A `/park` cycle saves
  learnings but doesn't surface what was saved — `/list-learnings --since <today>`
  closes that loop.

## Related

- [[save-learning]] — counterpart; the skill that creates the files this dashboard reads
- [[list-parks]] — sibling read-only dashboard, but for project state
- [[park]] — saves both project state and learnings; `/list-learnings --since`
  is a natural follow-up to verify a park run captured what you expected
