---
date: 2026-05-17
type: system
tags: [agent-config, pi-agent]
id: 81a09136-e399-5ce0-9c26-6dbd24344d1c
---

# Pi Agent Config

Pi loads `~/.pi/agent/AGENTS.md`, which is symlinked by the bootstrap to `system/pi-config/agents.md`.

## Pi-specific rules

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- Pi setup/wrapper/bootstrap assets live in `system/pi-config/`.
- Pi skills are installed under `~/.pi/agent/skills/`, as symlinks to the agnostic home `system/skills/` or to Pi-specific skills in `system/pi-config/skills/`.
- After changing public Pi config, run `scripts/privacy-scan.sh`.
- After changing private `local/` notes, run `scripts/sync-agentbrain-local.sh`.
