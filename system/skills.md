---
date: 2026-05-22
type: system
tags: [meta, skills]
id: de89875f-dacb-5f07-a964-f6ffc1ec171d
---

# Skills

Invoke a skill by typing its command. Any agent that reads this file can run them.

This is a **thin index** loaded every session — when you invoke a skill, read its
`SKILL.md` for the full procedure. Progressive disclosure keeps the per-session
context cheap; the detail lives once, in each skill's `SKILL.md`.

| Skill | What it does | Full procedure |
|-------|--------------|----------------|
| `/save-learning` | Save a real insight to `local/learnings/` | `system/skills/save-learning/SKILL.md` |
| `/save-troubleshoot` | Log a problem + solution | `system/skills/save-troubleshoot/SKILL.md` |
| `/project-update` | Create/update a project note in `local/projects/` | `system/skills/project-update/SKILL.md` |
| `/doctor` | Framework health audit (`scripts/doctor.sh`) | `system/skills/doctor/SKILL.md` |
| `/brain-review` | Quality + freshness review of stored knowledge | `system/skills/brain-review/SKILL.md` |
| `/brain-retro` | Retrospective over system, extensions, add-ons, backlog, and knowledge hygiene | `system/skills/brain-retro/SKILL.md` |
| `/brain-insights` | Surface work patterns from recent sessions | `system/skills/brain-insights/SKILL.md` |
| `/onboard` | Personalize preference scopes (focus-based: `<scope>` to do one area) | `system/skills/onboard/SKILL.md` |
| `/config` | Inspect/adjust config post-onboarding (focus-based: locale/addons/hooks/preferences/shell-rc) | `system/skills/config/SKILL.md` |
| `/capture-tool-info` | Capture tool/auth/service info into `local/` | `system/skills/capture-tool-info/SKILL.md` |
| `/addon-create` | Scaffold a new addon registry entry | `system/skills/addon-create/SKILL.md` |
| `/refactor-brain` | Plan + execute safe brain refactors | `system/skills/refactor-brain/SKILL.md` |
| `/opensrc` | Fetch dependency source for deeper context | `system/skills/opensrc/SKILL.md` |
| `/lightpanda` | Headless-browser web search/scrape | `system/skills/lightpanda/SKILL.md` |
| `/understand` | Knowledge graph of the agentBrain codebase | `system/skills/understand/SKILL.md` |
| `/understand-project` | Knowledge graph of an external project | `system/skills/understand-project/SKILL.md` |
| `/scanman` | Analyze a repo end-to-end with file inventory, dependency/import mapping, architecture graphs, runtime/dataflow charts, and redesign distillation | `system/skills/scanman/SKILL.md` |
| `/repo-distill` | Legacy alias for `/scanman` | `system/skills/scanman/SKILL.md` |
| `/journal` | Inspect/update the session-journal (show/save/task/archive/config) | `system/addons/session-journal/README.md` |
| `/selftest` | Agent-agnostic selftest — generic checks + section per detected agent (Claude Code, Pi, Copilot CLI, Gemini CLI) | `scripts/selftest.sh` (see also `scripts/selftest/README.md`) |
| `/add-locale` | Add a new UI language to `scripts/lib/_strings.sh` | `system/skills/add-locale/SKILL.md` |

`/doctor` validates the framework + guardrails; `/brain-review` reviews the quality
and freshness of stored knowledge.

## Authoring

**Patterns** — before writing a new skill, check `system/skill-patterns.md` to see
if your skill fits a known pattern (currently: **focus-based** for multi-scope
config/onboarding flows, **subcommand-based** for action-style skills). Pick the
matching surface or document why it doesn't fit. The pattern doc also has a
checklist; following it makes the skill predictable for users and consistent
across agents. Using `skill-creator`? Mention this pattern doc to it explicitly —
it's not in its training set.

New or substantially updated skills prefer this structure (progressive disclosure,
reviewability): **When to Use · Procedure · Pitfalls · Verification · References.**
Existing skills remain valid. `SKILL.md` frontmatter: `name`, `description`, optional
`argument-hint`, `user-invocable`, `resources`. `scripts/setup-skills.sh` installs every
skill into each capable agent; a skill that needs a tool/add-on self-gates (it documents
its prereq and simply can't run where the tool is absent).

## Add-ons

Optional, agent-agnostic tools live under `system/addons/<id>/` and are enabled per
machine via `local/addons/<id>/enabled`. Manage with `scripts/addons.sh`
(`status`/`install`/`enable`/`disable`/`check`). See `system/addons/README.md`.
