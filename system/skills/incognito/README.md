---
date: 2026-06-16
type: skill
tags: [skill, incognito, privacy, agentbrain]
status: active
id: 55b6a0b3-3e56-5686-a948-2bb0f0aa51dc
---

# incognito

Toggle agentBrain incognito mode — a read-only session where the brain can be
consulted but nothing new is written.

Reads (`brain_search` / `brain_read` / `brain_recent`) keep working; every write
path (learnings, projects, troubleshoot, memories, journal) is suppressed via a
single flag file in the active vault. Args: `on` / `off` / (none = status).

Backed by the `incognito` addon (`system/addons/incognito/`). See `SKILL.md` for
the toggle behavior.
