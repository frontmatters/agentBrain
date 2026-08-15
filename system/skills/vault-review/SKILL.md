---
name: vault-review
description: Periodic review of the agentBrain vault. Analyses notes for missing wiki-links, outdated info, patterns that should move to the agent-guidance file, and overall vault health. Use on /vault-review or when the vault needs maintenance.
---

# agentBrain Vault Review

Periodic analysis and improvement of the agentBrain vault.

## Vault location

```
~/agentBrain/
├── local/        ← user content (learnings, projects, sessions, references, backlog, addons)
└── system/       ← framework (rules, architecture, skills, addons-source, agent-config)
```

## Review steps

### 1. Vault-health check

Scan the vault for structural problems:

```bash
# Notes per top-level directory
find ~/agentBrain/local -name "*.md" -not -path "*/.git/*" -not -path "*/archive/*" \
    | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn

# Notes without frontmatter (should have `---` at line 1)
grep -rL "^---" ~/agentBrain/local/{learnings,projects,sessions,references,backlog}/ --include="*.md" 2>/dev/null

# Notes without wiki-links (candidates for orphaning)
grep -rL "\[\[" ~/agentBrain/local/{learnings,projects,references}/ --include="*.md" 2>/dev/null

# Doctor-level health (canonical)
bash ~/agentBrain/scripts/doctor.sh
```

`doctor.sh` is the source-of-truth health audit — start there. The grep commands above catch finer-grained content issues that doctor doesn't always surface.

### 2. Wiki-link integrity

- Find `[[broken-links]]` pointing at non-existent notes
- Identify notes that are referenced often but don't have their own note (candidates for new notes)
- Find isolated notes (no incoming or outgoing links)

```bash
# All wiki-link targets that don't resolve to a file
grep -roh "\[\[[^\]]*\]\]" ~/agentBrain/local/ \
    | sed -E 's/\[\[([^|\]]+).*\]\]/\1/' | sort -u \
    | while read t; do
        # crude resolution: find <slug>.md anywhere under local/
        if ! find ~/agentBrain/local -name "${t##*/}.md" -print -quit | grep -q .; then
            echo "broken: $t"
        fi
    done
```

### 3. Pattern discovery

In recent session-notes and learnings, look for:
- **Recurring problems** → should move to `local/learnings/troubleshooting.md`
- **Recurring decisions** → should move to the agent-guidance file (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, per agent)
- **Recurring workarounds** → should move to `local/learnings/patterns.md`
- **New projects** that don't have a `local/projects/<name>/` note yet

### 4. Agent-guidance sync check

Compare the agent-guidance file (`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`, plus any project-level ones) with the current vault state:
- Are there references to notes that no longer exist?
- Are important new patterns missing from it?
- Is the personal-preferences / thinking-model section still current?

### 5. Staleness check

Look for notes with:
- `status: active` but no updates in >30 days
- `confidence: low` that have never been upgraded
- Session-notes containing open items that were never picked up
- Backlog items with `status: open` that have been open >60 days (candidates for closing or escalation)

```bash
# Open backlog items
grep -lE "^status:[[:space:]]*open" ~/agentBrain/local/backlog/*.md \
    | xargs -I{} sh -c 'echo "$(grep -m1 ^date: {} | sed s/date://) — {}"' \
    | sort
```

### 6. Daily-notes review

- Check whether daily-notes are consistently maintained in `~/agentBrain/daily-notes/`
- Identify weeks without daily-notes (e.g. a week with 0 of 7 — flagged by the `weekly-review` addon)
- Suggest patterns from daily-notes that should be promoted to permanent notes (`local/references/` or `local/learnings/`)

The `weekly-review` addon (`local/sessions/weekly/<YYYY-WNN>.md`) already records `source_daily_notes` in its frontmatter — count = 0 is a signal that the daily-note habit isn't sticking yet.

## Output

After the review, write a report at `~/agentBrain/local/sessions/<YYYY-MM-DD>-vault-review.md`:

```markdown
---
date: YYYY-MM-DD
type: session
tags: [vault-review, meta]
projects: [agentbrain]
status: completed
id: <UUID5 via scripts/uuid5-gen.sh "local/sessions/<YYYY-MM-DD>-vault-review">
---

# Vault review YYYY-MM-DD

## Statistics
- Total notes: X
- Notes with wiki-links: X%
- Isolated notes: X
- Stale notes: X (open >30 days, status: active)
- Open backlog: X
- Daily-notes maintained: X / 7 last week

## Issues found
1. ...

## Improvements made
1. ...

## Recommendations
1. ...
```

## Frequency

- **Ideal**: every 2 weeks
- **Minimum**: monthly
- **Trigger**: when the user says `/vault-review` or after a major content burst (e.g. a multi-week project sprint that touched many notes)

## Related skills

- `brain-review` — narrower review skill (just structural + content quality, no CLAUDE.md sync)
- `brain-retro` — broader retrospective across system + addons + backlog + knowledge hygiene
- `doctor` — canonical structural health audit (run first; complements this skill)
- `brain-learn` — the continuous learning side of the same loop
