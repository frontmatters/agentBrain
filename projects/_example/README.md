---
date: 2026-05-18
type: system
tags: [projects, template, example]
id: 85688542-92c7-5135-a1b6-2829ec82a44f
---

# \_example

Template showing the expected structure for a project folder.

Every project in `local/projects/[name]/` should follow this layout. Copy these files as a starting point.

## Files

| File           | Required | Purpose                                  |
| -------------- | -------- | ---------------------------------------- |
| `index.md`     | ✅       | Project overview, status, phase          |
| `prd.md`       | Optional | Requirements and user stories            |
| `decisions.md` | Optional | Architecture decisions (ADR-light)       |
| `changelog.md` | Optional | Work completed, grouped by date          |
| `deploy.md`    | Optional | Deployment instructions and config       |
| `context.md`   | Optional | Technical context, dependencies, gotchas |

See `templates/project-*.md` for detailed templates.
