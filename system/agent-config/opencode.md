---
date: 2026-05-17
type: system
tags: [agent-config, opencode]
id: 4b0cf1c1-7d79-5bde-884f-3d7526159136
---

# OpenCode Agent Config

OpenCode reads instruction file paths from the `instructions` array in `~/.config/opencode/opencode.json`.

## How the integration is installed

`scripts/setup-opencode.sh` (run by `scripts/setup.sh` when OpenCode is detected):

- Writes the canonical pointer block (from `scripts/agentbrain-pointer.sh`) to `~/.config/opencode/agentbrain-pointer.md`.
- Registers that path in the `instructions` array of `~/.config/opencode/opencode.json` — merged into the existing config (created if absent), never overwritten. A malformed config fails visibly instead of being replaced.
- Already configured = the pointer file exists and is registered in the array; the script then skips (idempotent).

`scripts/uninstall.sh` removes both symmetrically (pointer file + `instructions` entry) and cleans a legacy agentBrain block from `system_prompt` in `~/.opencode/opencode.json` if an older setup wrote one.

## OpenCode-specific rules

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- Keep OpenCode config as pointers to files, not duplicated long instructions.
