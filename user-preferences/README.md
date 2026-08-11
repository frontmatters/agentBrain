---
date: 2026-05-18
type: system
tags: [preferences, meta]
id: 4127d89f-f79a-54e0-b8f0-fe8f7fa81772
---

# User Preferences

User preference templates. These are public examples — personalize them in `local/preferences/personal/`.

## Files

| File                   | Purpose                                |
| ---------------------- | -------------------------------------- |
| `Communication.md`     | Language, tone, response style         |
| `Decision-Making.md`   | How to handle trade-offs and ambiguity |
| `Design-Philosophy.md` | UI/UX and code design preferences      |
| `Tech-Stack.md`        | Preferred languages, frameworks, tools |
| `Workflow.md`          | Development workflow and habits        |

## How it works

Public files here are templates with placeholder content. Your personalized preferences belong in `local/preferences/personal/`.

Agents read preference scopes at session start:

- `local/preferences/organization/` — optional broader context
- `local/preferences/team/` — optional team context
- `local/preferences/personal/` — your individual preferences

Run `/onboard` to interactively create or update your private preference scopes.
