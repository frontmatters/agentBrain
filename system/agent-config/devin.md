---
date: 2026-05-17
type: system
tags: [agent-config, devin]
id: 4a3c55ba-4367-53f4-a078-d22e03192863
---

# Devin Desktop Agent Config

Devin Desktop (formerly Windsurf) runs Devin Local by default and retains Cascade.
`setup-devin.sh` installs an embedded pointer in `~/.config/devin/AGENTS.md`, unless
Claude import is on and `~/.claude/CLAUDE.md` already has a current pointer. In that
case the imported Claude rules provide the brain once, not twice. Cascade's existing
`~/.codeium/windsurf/memories/global_rules.md` remains current; setup never creates it.
The old `~/.windsurf/global_rules.md` loses only the agentBrain block.

Follow `system/agent-config/shared.md` and `system/rules.md`. Read any existing
`vault/preferences/organization/`, `vault/preferences/team/`, and
`vault/preferences/personal/` scopes and today's `vault/daily-notes/` note.
Keep pointers thin; shared behaviour belongs in `shared.md`.
