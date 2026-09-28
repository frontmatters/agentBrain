---
date: {{date}}
type: system
tags: [projects, meta]
id: {{uuid5}}
---

# Projects

Project registry and templates. Real project notes live in `vault/projects/[name]/`.

## Structure

- `index.md` — Registry of all projects (name + status only, no secrets)
- `_example/` — Template showing the expected folder structure

## Adding a project

Use `/project-update` or manually:

1. Create `vault/projects/[name]/index.md` (required)
2. Add optional files: `prd.md`, `decisions.md`, `changelog.md`, `deploy.md`, `context.md`
3. Register in `index.md` (name + status only)

See `templates/project-*.md` for file templates.
