---
date: 2026-05-17
type: system
tags: [agent-config, opencode]
id: 4b0cf1c1-7d79-5bde-884f-3d7526159136
---

# OpenCode Agent Config

OpenCode reads instruction file paths from the `instructions` array in `~/.config/opencode/opencode.json`.

## How the integration is installed

`scripts/setup/setup-opencode.sh` (run by `scripts/setup/setup.sh` when OpenCode is detected):

- Writes the canonical pointer block (from `scripts/agentbrain-pointer.sh`) to `~/.config/opencode/agentbrain-pointer.md`.
- Registers that path in the `instructions` array of `~/.config/opencode/opencode.json` — merged into the existing config (created if absent), never overwritten. A malformed config fails visibly instead of being replaced.
- Already current = the pointer file holds exactly what the generator writes now and is registered; the script then leaves it untouched. A pointer from an older layout is rewritten, and missing absolute paths with an agentBrain file name (left by older setups) are removed from `instructions`. Globs, URLs and existing paths stay.
- Grants read access to the brain under `permission.external_directory`: the brain alias (`~/agentBrain/**`) and the vault's real directory, both as absolute paths with `"allow"`. OpenCode otherwise asks before touching any path outside the project and refuses in a non-interactive run, so the agent saw the pointer but could not read a file it names. A user's own rule for the same path is kept; a global `external_directory` string is reported, not changed.

`scripts/uninstall.sh` removes both symmetrically (pointer file + `instructions` entry) and cleans a legacy agentBrain block from `system_prompt` in `~/.opencode/opencode.json` if an older setup wrote one.

## OpenCode-specific rules

- Follow `system/agent-config/shared.md` and `system/rules.md`.
- Keep OpenCode config as pointers to files, not duplicated long instructions.
