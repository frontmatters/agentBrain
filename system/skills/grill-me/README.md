---
date: 2026-06-11
type: system
tags: [skill, grill-me, knowledge-extraction, onboarding]
id: 421980a2-7518-5f9d-8195-101aa99b5698
---

# grill-me

Knowledge-extraction interview skill. Asks 15–25 focused questions to pull tacit knowledge out of the user's head and into `local/preferences/`.

## Purpose

The brain is only as useful as the context it holds. `/grill-me` seeds that context by relentlessly interviewing the user — covering business, workflow, goals, clients, tech-stack, and communication preferences. Extracted knowledge is written to `local/preferences/` as structured markdown.

## Usage

```
/grill-me                  # full session — all focus areas
/grill-me business         # only business context
/grill-me workflow         # only workflow and rhythms
/grill-me goals            # only 90-day / 1-year goals
/grill-me clients          # only client context
/grill-me tech-stack       # only technology preferences
/grill-me communication    # only tone/format preferences
```

## Output

- Updates or creates files under `local/preferences/personal/`
- May also write to `local/preferences/organization/` or `local/preferences/team/`
- Optionally writes `local/projects/<name>/context.md` for project-specific context

## When to run

- At brain setup (first time, no preferences yet)
- When starting a new business domain or project
- Quarterly refresh
- Any time the brain "doesn't know you well enough"
