---
date: 2026-07-07
type: system
tags: [skill, namecheck]
id: eb3960dd-5e71-5102-b383-cf3207c2ea79
---

# namecheck

Availability sweep for product/brand names — with conflict context.

## Purpose

Before claiming a name, sweep every claimable namespace in one run: npm
(package + scope), GitHub user/org (+ defensive variants), Open VSX, VS Code
Marketplace, Homebrew (formula + cask), the common TLDs, X/Twitter, and
Reddit. For every TAKEN resource the sweep fetches what's actually behind it
(description, owner, site title) so conflict risk can be judged — not just
"taken".

## Usage

```bash
bash ~/agentBrain/system/skills/namecheck/sweep.sh <name> [<name2> ...]
```

Multiple names produce side-by-side reports for shortlist decisions. The
skill layer (`SKILL.md`) adds the conflict-judgment rubric, ranking matrix,
and post-sweep follow-ups (trademark search, defensive-namespace plan).

## Versioning

`VERSION` (SemVer) + `CHANGELOG.md`, bumped per the release flow documented
in the changelog. Smoke test: `bash sweep.sh cortexa` (known-taken) and
`bash sweep.sh encephr` (mostly free).
