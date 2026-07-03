---
date: 2026-05-21
type: system
tags: [meta, context, memory]
id: cf2ae652-18f0-5b53-8bfb-1b30a3ce6fce
---

# Context Tiers

Use tiers to keep agent context focused without changing the public/private boundary.

## Measured baseline

As of 2026-05-26, the public startup set measured about **~19k characters / ~4.8k tokens**. The hot set has since been re-anchored to the installed pointer block (`scripts/agentbrain-pointer.sh`); `system/tools.md` and `system/lifecycle.md` are warm (on demand):

| Tier               | Files                                                                                                                          | Approx size  |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------- | ------------ |
| Hot public startup | `learnings/patterns.md`, `learnings/troubleshooting.md`, `system/rules.md`, `system/agent-config/shared.md` + the client config, `system/skills.md` | ~5k tokens |

Skill procedures (`SKILL.md`), the operations index (`system/tools.md`), warm reference (`system/reference.md`), and this tier policy itself load on demand, not hot. Do not promote content to hot unless it is repeatedly needed across sessions.

## Hot context

The canonical hot reading list is **`system/rules.md` Step 1** (identical to the installed pointer block) — this file does not restate it. In short: the compact public files above, plus `local/sessions/startup-context.md` and preference scopes when present. Hot context should be compact, stable, and broadly useful.

## Warm context

Load on demand when relevant:

- `local/preferences/{organization,team,personal}/`
- `local/projects/<name>/index.md` and optional project files
- `local/learnings/`
- `local/integrations/` and `local/security/` before credential-sensitive work
- skill reference files and templates

Warm context may contain real user/project knowledge and therefore belongs in `local/` when private.

## Cold context

Search or summarize only when needed:

- session archives and journals
- `local/reports/`
- `local/research/`
- stale or archived notes
- large transcripts or generated artifacts

Cold context should not be pasted wholesale into prompts. Prefer summaries, focused excerpts, file paths, or search-backed lookup.

## Rules

- Public files describe HOW/WHERE only; real WHAT stays in `local/`.
- Measure before optimizing context tiers.
- Promote cold/warm content to hot only when it is repeatedly needed across sessions.
- If tool, job, or command output is re-injected into agent context, scan or summarize it first and truncate large output.

## Related

- [[rules]]
- [[skills]]
- [[lifecycle]]
