---
date: 2026-05-18
type: system
tags: [system, meta]
id: 3f2aa50d-9ef2-5e70-9bb4-6bea86564dc1
---

# System

Core framework rules, agent configuration, and integrations.

## Files

| File                   | Purpose                                                              |
| ---------------------- | -------------------------------------------------------------------- |
| `Rules.md`             | Canonical policy: public/private, write locations, quality standards |
| `Skills.md`            | Available slash commands and their usage                             |
| `Lifecycle.md`         | Project PDCA lifecycle phases (plan → build → check → learn)         |
| `Architecture.md`      | High-level architecture and design decisions                         |
| `Security-Guidance.md` | Privacy and security rules for public content                        |
| `sessions.md`          | Session continuity system documentation                              |

## Subdirectories

| Directory       | Purpose                                                         |
| --------------- | --------------------------------------------------------------- |
| `agent-config/` | Agent startup instructions (shared.md + agent-specific configs) |
| `pi-config/`    | Pi-specific setup: extensions, skills, bootstrap                |
| `integrations/` | Third-party tool integrations (opensrc, etc.)                   |

Agents read these files at session start. See `system/agent-config/shared.md` for the startup checklist.
