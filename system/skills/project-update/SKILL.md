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

Create or update a project in `vault/projects/` (personal, gitignored).

## Steps

> **Context routing.** A project may belong to a sealed owner-space. `new-note.sh`
> infers the space per-write (code-root / `AGENTBRAIN_CONTEXT`). When the agent
> harness CWD differs from the repo being worked on, pass `--from <repo-path>` so
> the actual code-root is used. If owner-specific path signals still cannot tell,
> ASK which owner-space (enumerate `vault/spaces/*/`) or personal, then pass
> `--context <slug>`. Never silently save owner-work to personal. See the Spaces /
> ownership policy in `system/rules.md`.

### New project

1. **Check if the project already exists** in `vault/projects/`
2. **Create `vault/projects/[name]/`** subfolder with at minimum `index.md`:
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

1. **Read the existing files** in `vault/projects/[name]/`
2. **Update the relevant file:**
   - New milestone -> add to `index.md` `## Progress` with date
   - Architecture decision -> append an ADR to `decisions.md` (create if missing). Always fill **Alternatives** — the option you rejected and why is the most valuable field.
   - Status changed -> update `status` in `index.md` frontmatter
   - Project completed -> set `status: done`
   - Work completed -> add entry to `changelog.md`
3. **Update the `date` in frontmatter** of modified files to today
4. **Do not update `projects/index.md` for real/private projects.** Only update the shared index for public/example projects.

### Project insight becomes a general pattern?

If a project-specific insight is broadly applicable:

1. Move it to `learnings/patterns.md`
2. Leave a cross-reference in the project note

## Decisions (ADRs)

Architecture decisions live in one `decisions.md` per **owning context** — a project
(`vault/projects/<slug>/decisions.md`) or a space. Everything belongs to an owner; there is
no free-floating decision log. Framework-wide choices (about agentBrain itself) belong to the
`agentbrain-framework` project.

- **Format**: ADR-light (`templates/project-decisions.md`). Always fill **Alternatives** — the
  rejected option and why is the field that stops you re-litigating later.
- **Numbering**: `ADR-NNN` is a *local sequence within the owner* — it restarts at 001 per
  `decisions.md` and does **not** collide across projects. The globally unique id is the
  UUID5-from-path in frontmatter, not the ADR number.
- **Citing a specific ADR**: use a heading-anchor wikilink, e.g.
  `[[codemap/decisions#ADR-002 Convert Flux oklch tokens to rgb]]`, so a learning can point at
  one decision without splitting ADRs into separate files.
- **Scaffolding**: `scripts/new-note.sh decisions vault/projects/<slug>/decisions` — the
  project's `index.md` must exist first (a project owns its decisions).

## References

- Templates: `templates/project-*.md`
- Example: `projects/_example/`
- Rules: `system/rules.md`
