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
| `/add-locale` | Add a new UI language to `scripts/lib/_strings.sh` | `system/skills/add-locale/SKILL.md` |
| `/addon-create` | Scaffold a new addon registry entry | `system/skills/addon-create/SKILL.md` |
| `/addons` | Manage addons via `scripts/addons.sh` (status/install/enable/disable, launchd jobs) | `system/skills/addons/SKILL.md` |
| `/brain-explain` | Render an agentBrain note into a themed, self-contained HTML explainer | `system/skills/brain-explain/SKILL.md` |
| `/explain-branch` | Generate a themed HTML explainer of a git branch's commits + merge/landing strategy, via brain-explain | `system/skills/explain-branch/SKILL.md` |
| `/queue` | Manage the work queue + dispatch via `scripts/queue.sh` (add/start/done/cancel/dispatch/board) | `system/skills/queue/SKILL.md` |
| `/brain-extract` | Bundle a project's (or a space's) knowledge into a portable `.brain-package/` | `system/skills/brain-extract/SKILL.md` |
| `/brain-forget` | Soft-delete a note to `local/.trash/forget/` (recoverable via `/brain-recall`) | `system/skills/brain-forget/SKILL.md` |
| `/brain-hide` | Hide a note from listings (`hidden: true`) without deleting it | `system/skills/brain-hide/SKILL.md` |
| `/brain-insights` | Surface work patterns from recent sessions | `system/skills/brain-insights/SKILL.md` |
| `/brain-purge` | Permanently delete forget-batches from trash (explicit confirmation, never skippable) | `system/skills/brain-purge/SKILL.md` |
| `/brain-recall` | Restore a forgotten note from `local/.trash/forget/` | `system/skills/brain-recall/SKILL.md` |
| `/brain-restore` | Restore a `.brain-package/` back into the vault | `system/skills/brain-restore/SKILL.md` |
| `/brain-retro` | Retrospective over system, extensions, add-ons, backlog, and knowledge hygiene | `system/skills/brain-retro/SKILL.md` |
| `/brain-review` | Quality + freshness review of stored knowledge | `system/skills/brain-review/SKILL.md` |
| `/brain-unhide` | Restore a hidden note to listings | `system/skills/brain-unhide/SKILL.md` |
| `/capture-tool-info` | Capture tool/auth/service info into `local/` | `system/skills/capture-tool-info/SKILL.md` |
| `/component-motion` | Scroll/stagger/magnetic/physics motion (GSAP, Lenis, AOS, anime.js, Motion, Lottie, Rive) on web components via clean seams, reduced-motion-safe | `system/skills/component-motion/SKILL.md` |
| `/config` | Inspect/adjust config post-onboarding (focus-based: locale/addons/hooks/preferences/shell-rc) | `system/skills/config/SKILL.md` |
| `/cro-optimize` | Conversion-rate optimization: benefit-led CTAs, social proof, trust microcopy, objection-handling FAQ, funnel/A-B-testing | `system/skills/cro-optimize/SKILL.md` |
| `/doctor` | Framework health audit (`scripts/doctor.sh`) | `system/skills/doctor/SKILL.md` |
| `/grill-me` | Knowledge-extraction interview into local preferences/notes | `system/skills/grill-me/SKILL.md` |
| `/incognito` | Toggle read-only session mode (consult the brain, write nothing) | `system/skills/incognito/SKILL.md` |
| `/lightpanda` | Headless-browser web search/scrape | `system/skills/lightpanda/SKILL.md` |
| `/list-hidden` | Dashboard of hidden (and optionally forgotten) notes | `system/skills/list-hidden/SKILL.md` |
| `/list-learnings` | List recent learnings with date, tags, and title | `system/skills/list-learnings/SKILL.md` |
| `/list-parks` | List parked (paused/blocked) projects | `system/skills/list-parks/SKILL.md` |
| `/list-projects` | List all projects with status, priority, and description | `system/skills/list-projects/SKILL.md` |
| `/namecheck` | Sweep a product name across npm/GitHub/marketplaces/brew/domains/social — and report what's behind each TAKEN resource | `system/skills/namecheck/SKILL.md` |
| `/onboard` | Personalize preference scopes, addons (essentials recommended), locale, and release channel (focus-based) | `system/skills/onboard/SKILL.md` |
| `/opensrc` | Fetch dependency source for deeper context | `system/skills/opensrc/SKILL.md` |
| `/park` | Park work-in-progress for reliable later resume | `system/skills/park/SKILL.md` |
| `/peer-review` | Async cross-agent document review via the event-bus | `system/skills/peer-review/SKILL.md` |
| `/project-update` | Create/update a project note in `local/projects/` | `system/skills/project-update/SKILL.md` |
| `/brain-architect` | Evidence-gated architecture analysis of an existing system, executable by a cheaper model: building blocks, six constraint lenses, decision records, open-questions ledger, deterministic `validate.sh` gate | `system/skills/brain-architect/SKILL.md` |
| `/space-docs` | Produce a self-contained, transferable docs bundle (README + ARCHITECTURE + ROADMAP + MEMORY, rendered diagrams) that stands on its own boundary; deterministic `validate.sh` fails on machine-local paths, private/vault refs, and dead links | `system/skills/space-docs/SKILL.md` |
| `/promote` | Move artifacts between `local/X/` ↔ `system/X/` mirror folders | `system/skills/promote/SKILL.md` |
| `/refactor-brain` | Plan + execute safe brain refactors | `system/skills/refactor-brain/SKILL.md` |
| `/relevant` | Check whether open work is still needed (still-needed CLI) | `system/skills/relevant/SKILL.md` |
| `/repo-distill` | Legacy alias for `/scanman` | `system/skills/repo-distill/SKILL.md` |
| `/save-learning` | Save a real insight to `local/learnings/` | `system/skills/save-learning/SKILL.md` |
| `/save-troubleshoot` | Log a problem + solution | `system/skills/save-troubleshoot/SKILL.md` |
| `/scanman` | Analyze a repo end-to-end: architecture, dependencies, runtime flows, redesign distillation | `system/skills/scanman/SKILL.md` |
| `/shorthand` | Manage personal abbreviations (agent-agnostic glossary + shell aliases) | `system/skills/shorthand/SKILL.md` |
| `/skills` | Manage the local skill lifecycle: list/sources/audit/sync + add-repo (thin router over skill-finder/promote/addons) | `system/skills/skills/SKILL.md` |
| `/technique-transplant` | Harvest a reference site's design/motion technique and re-apply it onto your own components | `system/skills/technique-transplant/SKILL.md` |
| `/treasure-hunt` | Turn one found bug/anti-pattern instance into a full sweep + durable detector, not a one-off fix | `system/skills/treasure-hunt/SKILL.md` |
| `/understand` | Knowledge graph of the agentBrain codebase | `system/skills/understand/SKILL.md` |
| `/understand-project` | Knowledge graph of an external project | `system/skills/understand-project/SKILL.md` |
| `/unpark` | Resume a parked project (reads index + learnings, executes backlog) | `system/skills/unpark/SKILL.md` |
| `/wash-vault` | Detect/fix id-mismatches, missing frontmatter, unsafe filenames (dry-run default) | `system/skills/wash-vault/SKILL.md` |
| `/web-3d` | 3D/WebGL/WebXR on the web (Three.js, R3F, Babylon, PlayCanvas, PixiJS, Spline, A-Frame, lightweight effects); engine-selection + performance/a11y guardrails | `system/skills/web-3d/SKILL.md` |
| `/weekly-review` | Weekly markdown summary of vault activity (learnings/projects/backlog/sessions) | `system/skills/weekly-review/SKILL.md` |
| `/youtube-digest` | Sync YouTube channel transcripts into the vault, or fetch a single video | `system/skills/youtube-digest/SKILL.md` |

Some commands ship with an addon or script rather than a skill directory:
`/journal` (session-journal addon — `system/addons/session-journal/README.md`) and
`/selftest` (`scripts/selftest.sh`, see `scripts/selftest/README.md`).

`/doctor` validates the framework + guardrails; `/brain-review` reviews the quality
and freshness of stored knowledge.

## Spaces

Spaces are sealed owner compartments under `local/spaces/<slug>/` (see `system/rules.md` → *Spaces / ownership*, and the full workflow in `docs/spaces.md`). Writes route into a space **per-write via context inference** (`system/lib/context.sh`) — the CWD's code-root, `AGENTBRAIN_CONTEXT=<slug>`, or an explicit `--context <slug>` on `new-note`. Create a space with `scripts/new-space.sh`; seal + back it up to its own private remote with `scripts/sync-space.sh`. The old `active-space` session mode / `.active-space` marker is **decommissioned**.

Remaining tail (not yet built): `relevant`/still-needed scoping and a per-space MOC.

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
