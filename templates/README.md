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
| `project-index.md`     | `vault/projects/[name]/index.md`     |
| `Project-PRD.md`       | `vault/projects/[name]/prd.md`       |
| `Project-Decisions.md` | `vault/projects/[name]/decisions.md` |
| `Project-Changelog.md` | `vault/projects/[name]/changelog.md` |
| `Project-Deploy.md`    | `vault/projects/[name]/deploy.md`    |
| `Project-Context.md`   | `vault/projects/[name]/context.md`   |

## Local starters

`local-starters/` contains templates that `scripts/setup/setup.sh` copies to `vault/` on first run (only if the target doesn't exist yet).
