---
date: 2026-05-18
type: system
tags: [skill, onboard]
id: 645a2507-e3c2-5819-b94e-3282a99e95ef
---

# onboard

Interactive onboarding skill for new agentBrain users.

## Purpose

Personalizes preference scopes under `local/preferences/`:

- `personal/` — always used; individual language, stack, workflow, design and decision preferences
- `organization/` — optional broader organization context
- `team/` — optional team-specific agreements

## Usage

```
/onboard
/onboard tech-stack
/onboard organization
/onboard team
```

Run on first setup or when preferences are incomplete. The flow starts with personal preferences, then asks whether organization or team scopes are relevant.
