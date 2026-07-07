---
date: 2026-05-17
type: system
tags: [agent-config, windsurf]
id: 037ac6e3-e7dc-5855-b2ed-f3f9b85f12d2
---

# Windsurf Agent Config

Windsurf uses a global rules pointer installed by `scripts/setup.sh`.

## Recommended pointers

- Preference scopes: read any existing files under `${VAULT}/local/preferences/organization/`, `${VAULT}/local/preferences/team/`, and `${VAULT}/local/preferences/personal/`.
- **Daily note**: `${VAULT}/local/daily-notes/$(date +%F).md` (auto‑created by `ensure-daily-note.sh`)

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- The setup pointer is appended to `~/.codeium/windsurf/memories/global_rules.md` when Windsurf is detected.
- Keep the global pointer thin; detailed shared behaviour belongs in `shared.md`.
