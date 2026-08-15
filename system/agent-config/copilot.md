---
date: 2026-05-17
type: system
tags: [agent-config, copilot]
id: c7b9d0bc-13c3-5b5a-a5f9-d18723d6399a
---

# Copilot Agent Config

Copilot reads `.github/copilot-instructions.md` as the tool-specific entrypoint.

## Recommended pointers

- Preference scopes: read any existing files under `${VAULT}/local/preferences/organization/`, `${VAULT}/local/preferences/team/`, and `${VAULT}/local/preferences/personal/`.
- **Daily note**: `${VAULT}/local/daily-notes/$(date +%F).md` (auto‑created by `ensure-daily-note.sh`)

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- Keep `.github/copilot-instructions.md` thin; detailed shared behaviour belongs here or in `shared.md`.
- Copilot reads skills from `.github/skills/`, which are symlinks into the agnostic home `system/skills/` (where skills are actually authored).
- Real learnings and project context go to `local/`, not public `learnings/`, unless explicitly sanitized for the public framework.
