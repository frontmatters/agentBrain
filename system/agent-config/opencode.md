---
date: 2026-05-17
type: system
tags: [agent-config, opencode]
id: 4b0cf1c1-7d79-5bde-884f-3d7526159136
---

# OpenCode Agent Config

OpenCode reads instruction file paths from `~/.config/opencode/opencode.json`.

## OpenCode-specific rules

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- `scripts/setup.sh` adds the canonical public instruction files to the OpenCode `instructions` array when OpenCode is detected.
- Keep OpenCode config as pointers to files, not duplicated long instructions.
