---
date: 2026-05-18
type: system
tags: [templates, meta]
id: 19b26523-888e-5dd7-838e-83d88e8ffd88
---

# Templates

File templates for agentBrain notes. Copy these as starting points.

## Note templates

| Template      | Used for                   |
| ------------- | -------------------------- |
| `learning.md` | General learning / insight |
| `Session.md`  | Session log entry          |
| `Daily.md`    | Daily note                 |
| `Project.md`  | Generic project file       |

## Project templates

| Template               | Creates                              |
| ---------------------- | ------------------------------------ |
| `project-index.md`     | `local/projects/[name]/index.md`     |
| `Project-PRD.md`       | `local/projects/[name]/prd.md`       |
| `Project-Decisions.md` | `local/projects/[name]/decisions.md` |
| `Project-Changelog.md` | `local/projects/[name]/changelog.md` |
| `Project-Deploy.md`    | `local/projects/[name]/deploy.md`    |
| `Project-Context.md`   | `local/projects/[name]/context.md`   |

## Local starters

`local-starters/` contains templates that `scripts/setup.sh` copies to `local/` on first run (only if the target doesn't exist yet).
