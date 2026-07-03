---
name: project-update
description: Create a new project subfolder or update an existing one in agentBrain. Use for a new project, milestone, architecture decision, or status change.
related: [list-projects]
argument-hint: Project name and what you want to record
user-invocable: true
resources:
  - templates/project-index.md
  - templates/project-prd.md
  - templates/project-decisions.md
  - templates/project-deploy.md
  - templates/project-changelog.md
  - templates/project-context.md
  - projects/_example/index.md
  - system/rules.md
---

# Project Update

Create or update a project in `local/projects/` (personal, gitignored).

## Steps

### New project

1. **Check if the project already exists** in `local/projects/`
2. **Create `local/projects/[name]/`** subfolder with at minimum `index.md`:
   - Use `templates/project-index.md` as template
   - Generate UUID5 for `id` field
   ```yaml
   ---
   date: YYYY-MM-DD
   type: project
   tags: [relevant, tags]
   status: active/paused/done
   priority: high/medium/low
   id: <UUID5>
   ---
   ```
3. **Fill in the sections** of `index.md`:
   - `## Goal` -- what this project does and why
   - `## Setup` -- tech stack, repo location, important commands
   - `## Progress` -- milestones with dates
   - `## Related` -- links to learnings, other projects
4. **Create optional files** as needed:
   - `prd.md` -- requirements, user stories (template: `templates/project-prd.md`)
   - `decisions.md` -- ADR-light records (template: `templates/project-decisions.md`)
   - `deploy.md` -- deploy config (template: `templates/project-deploy.md`)
   - `changelog.md` -- change log (template: `templates/project-changelog.md`)
   - `context.md` -- context map (template: `templates/project-context.md`)
5. **Do not update `projects/index.md` for real/private projects.** Only add public/example projects to the shared index.

### Updating an existing project

1. **Read the existing files** in `local/projects/[name]/`
2. **Update the relevant file:**
   - New milestone -> add to `index.md` `## Progress` with date
   - Architecture decision -> add to `decisions.md` (create if missing)
   - Status changed -> update `status` in `index.md` frontmatter
   - Project completed -> set `status: done`
   - Work completed -> add entry to `changelog.md`
3. **Update the `date` in frontmatter** of modified files to today
4. **Do not update `projects/index.md` for real/private projects.** Only update the shared index for public/example projects.

### Project insight becomes a general pattern?

If a project-specific insight is broadly applicable:

1. Move it to `learnings/patterns.md`
2. Leave a cross-reference in the project note

## References

- Templates: `templates/project-*.md`
- Example: `projects/_example/`
- Rules: `system/rules.md`
