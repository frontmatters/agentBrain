---
date: 2026-05-20
type: system
tags: [agent-config, gemini]
id: 061e46b8-8d1f-5b43-8a33-9694410bbf4d
---

# Gemini CLI Agent Config

Gemini CLI reads hierarchical context from `GEMINI.md` files. The global user context file is `~/.gemini/GEMINI.md`.

## Gemini-specific rules

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- `scripts/setup.sh` appends a thin agentBrain pointer to `~/.gemini/GEMINI.md` when Gemini CLI is detected or when `~/.gemini/` already exists.
- Keep `~/.gemini/GEMINI.md` as a pointer file; detailed shared behaviour belongs in `shared.md`.
- Preference scopes live under:
  - `local/preferences/organization/`
  - `local/preferences/team/`
  - `local/preferences/personal/`
- Daily notes live under `local/daily-notes/`.
- Use `/memory refresh` in Gemini CLI after pointer changes if an existing session is already running.
