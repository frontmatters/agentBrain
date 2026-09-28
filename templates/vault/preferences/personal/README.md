---
date: {{date}}
type: system
tags: [preferences, meta]
id: {{uuid5}}
---

# User Preferences

User preference templates. These are public examples — personalize them in `vault/preferences/personal/`.

## Files

| File                   | Purpose                                |
| ---------------------- | -------------------------------------- |
| `Communication.md`     | Language, tone, response style         |
| `Decision-Making.md`   | How to handle trade-offs and ambiguity |
| `Design-Philosophy.md` | UI/UX and code design preferences      |
| `Tech-Stack.md`        | Preferred languages, frameworks, tools |
| `Workflow.md`          | Development workflow and habits        |

## How it works

Public files here are templates with placeholder content. Your personalized preferences belong in `vault/preferences/personal/`.

Agents read preference scopes at session start:

- `vault/preferences/organization/` — optional broader context
- `vault/preferences/team/` — optional team context
- `vault/preferences/personal/` — your individual preferences

Run `/onboard` to interactively create or update your private preference scopes.
