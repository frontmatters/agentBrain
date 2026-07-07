---
date: 2026-05-18
type: system
tags: [skill, onboard]
id: 645a2507-e3c2-5819-b94e-3282a99e95ef
---

# onboard

Interactive onboarding skill for new agentBrain users.

## Purpose

Walks through the full first-time setup, one scope at a time (skip-if-done):

1. **Personal preferences** (always) — language, stack, workflow, design and decision preferences under `local/preferences/personal/`
2. **Organization scope** (optional) — broader organization context under `local/preferences/organization/`
3. **Team scope** (optional) — team-specific agreements under `local/preferences/team/`
4. **Addons** — recommended essentials first (from `scripts/lib/essential-addons.txt`), then the remaining opt-in addons via `scripts/addons.sh`
5. **Locale** — UI language for agentBrain scripts (`AGENTBRAIN_LOCALE`), supported codes derived from `scripts/lib/_strings.sh`
6. **Release channel & updates** — channel (`stable`/`prerelease`/`edge`) via `scripts/channel.sh` and the `auto_update` mode in `local/update/config.json`

## Usage

```
/onboard
/onboard tech-stack
/onboard organization
/onboard team
/onboard addons
/onboard locale
/onboard channel
```

Run on first setup or when configuration is incomplete. Follows the focus-based
skill pattern: walk-all by default, walk-one with a focus argument, idempotent
per scope. For post-onboarding inspection and tweaks, use `/config`.
