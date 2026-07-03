---
name: save-learning
description: Save a new technical insight to agentBrain. Use when you discover a pattern, workaround, or technical fact that is valuable for future sessions.
related: [list-learnings]
argument-hint: Describe the insight you want to save
user-invocable: true
resources:
  - local/learnings/patterns.md
  - local/learnings/troubleshooting.md
  - templates/learning.md
  - system/rules.md
---

# Save Learning

Public = HOW/WHERE. Private = WHAT. Save real discoveries in `local/`.

Save a new insight to the private local knowledge layer so user discoveries are not published.

## Steps

**First — route by active space.** Resolve it: `bash scripts/active-space.sh resolve`.
If it prints a slug, the insight belongs to that **sealed space**, not your shared
vault. Create it under `local/spaces/<slug>/learnings/` via `new-note.sh` (it sets a
path-correct UUID5 + `space:` field and already defaults to the active space):

```bash
bash scripts/new-note.sh learning learnings/<name> --space <slug>
```

then fill the body. **Never** write a space's learning to the shared `local/learnings/`
— that leaks confidential client/employer knowledge into your personal sync. If the
output is empty (no active space), continue with the normal flow below.

1. **Determine the type of insight:**
   - Recurring pattern (seen 2x+) -> add to `local/learnings/patterns.md`
   - Pattern seen 1st time -> add to `local/learnings/patterns.md` with `confidence: low`, note "seen 1x"
   - New technical insight -> create `local/learnings/[category].md` (lowercase/kebab-case)

   **Learnings are flat files + frontmatter `tags` (+ UUID + `[[wiki-links]]`), not folders.**
   Don't create topic subfolders under `learnings/` — categorize with `tags`, which are
   multi-dimensional and searchable. The only sanctioned subfolder is `extracted/`
   (machine-generated auto-extraction). Enforced by `scripts/check-learnings-structure.sh`.

2. **Check if it already exists:**
   - Read the relevant file
   - If the insight is already there -> UPDATE the existing entry
   - If it is new -> add a new section

3. **Write with the correct format:**
   - Updating an existing file: add a `## Section`
   - Creating a new file: use this frontmatter:
     ```yaml
     ---
     date: YYYY-MM-DD
     type: learning
     tags: [relevant, tags]
     confidence: high/medium/low/retracted
     source: session/documentation
     id: <UUID5>
     ---
     ```

4. **Validate:**
   - Is it actionable? (not just "interesting")
   - Is it proven? (no speculation)
   - Is it concise? (no prose)

5. **Confirm to the user** what you saved and where.

## References
- Template: `templates/learning.md`
- Existing patterns: `local/learnings/patterns.md`
- Rules: `system/rules.md`
