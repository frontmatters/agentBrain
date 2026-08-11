---
date: 2026-05-22
type: system
tags: [agent-config, copilot-cli]
id: d8c08d0d-2112-5c7e-a187-270f43e8f2e7
---

# GitHub Copilot CLI Agent Config

The GitHub Copilot CLI (the `copilot` command) reads personal global instructions from
`$HOME/.copilot/copilot-instructions.md` — this is where `setup-copilot-cli.sh` writes the
agentBrain pointer. It is a different product from the VS Code Copilot extension (see
`system/agent-config/copilot.md`), with its own `~/.copilot/` config tree.

## Recommended pointers

- Preference scopes: read any existing files under `${VAULT}/local/preferences/organization/`, `${VAULT}/local/preferences/team/`, and `${VAULT}/local/preferences/personal/`.
- **Daily note**: `${VAULT}/local/daily-notes/$(date +%F).md` (auto-created by `ensure-daily-note.sh`)
- Follow `system/agent-config/shared.md` and `system/rules.md`.

## CLI specifics

- Global instructions: `$HOME/.copilot/copilot-instructions.md` (written by setup).
- Per-repo: a root `AGENTS.md`, `CLAUDE.md`, or `GEMINI.md` is read automatically; extra
  dirs via the `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` env var.
- Skills: `~/.copilot/skills` (or `~/.agents/skills`); custom agents: `~/.copilot/agents/*.agent.md`.
- Real learnings and project context go to `local/`, not public `learnings/`.
