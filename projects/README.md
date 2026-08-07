---
date: 2026-05-18
type: system
tags: [projects, meta]
id: ecbebbc1-96e5-5204-8130-c189abd02e9f
---

# Projects

Project registry and templates. Real project notes live in `local/projects/[name]/`.

## Structure

- `index.md` — Registry of all projects (name + status only, no secrets)
- `_example/` — Template showing the expected folder structure

## Adding a project

Use `/project-update` or manually:

1. Create `local/projects/[name]/index.md` (required)
2. Add optional files: `prd.md`, `decisions.md`, `changelog.md`, `deploy.md`, `context.md`
3. Register in `index.md` (name + status only)

See `templates/project-*.md` for file templates.
