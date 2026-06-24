---
date: 2026-05-17
type: system
tags: [agent-config, entrypoints]
id: 11f1ee98-793a-5218-a87b-af46c25245ae
---

# Agent Config

Uniform public configuration layer for agent entrypoints.

## Files

- `shared.md` — shared behaviour used by all agents.
- `pi.md` — Pi-specific instructions.
- `copilot.md` — GitHub Copilot-specific instructions.
- `vscode-copilot.md` — VS Code Copilot setup notes.
- `claude.md` — Claude/Claude Code-specific instructions.
- `windsurf.md` — Windsurf-specific setup notes.
- `opencode.md` — OpenCode-specific setup notes.
- `gemini.md` — Gemini CLI-specific setup notes.
- `cline.md` — Cline-specific setup notes.
- `cursor.md` — Cursor-specific setup notes.
- `obsidian.md` — Obsidian vault notes.

## Entry points

Tool-required entrypoint files stay in their conventional locations and point here:

- Pi: `system/pi-config/agents.md`
- Copilot: `.github/copilot-instructions.md`
- Claude: `CLAUDE.md`
- Windsurf: `~/.codeium/windsurf/memories/global_rules.md` pointer installed by `scripts/setup-windsurf.sh`
- OpenCode: `~/.config/opencode/opencode.json` instructions installed by `scripts/setup-opencode.sh`
- Gemini CLI: `~/.gemini/GEMINI.md` pointer installed by `scripts/setup-gemini-cli.sh`
- Cline: `~/Documents/Cline/Rules/agentBrain.md` pointer installed by `scripts/setup-cline.sh`
- VS Code Copilot: `settings.json` written by `scripts/setup-copilot.sh`
- Cursor: `~/.cursor/User/settings.json` written by `scripts/setup-cursor.sh`

All of the above are run during setup by `scripts/setup-agent-integrations.sh` (which `scripts/setup.sh` calls), each only when its client is detected.
- Obsidian: open checkout as a vault

`system/rules.md` remains canonical for public/private boundaries and write locations.
