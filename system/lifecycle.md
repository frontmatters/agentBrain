---
date: 2026-03-24
type: system
tags: [meta, lifecycle, pdca]
id: b54e2807-1d0a-5626-952b-b2c8024de222
---

# Project Lifecycle

Projects follow a PDCA cycle: Plan, Do, Check, Act.
The current phase is stored in `index.md` frontmatter as `phase:`.

## Phases

### plan

Define what to build and why.

**Read**: `prd.md`, `decisions.md`
**Do**:
- Write or refine requirements in `prd.md`
- Record architecture decisions in `decisions.md`
- Define user stories: `- [ ] US-XX: description`
- Set acceptance criteria

**Transition to `build`**: when PRD has at least one user story and key decisions are recorded.

### build

Execute the plan. This is where dev-loop or manual development happens.

**Read**: `prd.md`, `decisions.md`, `context.md`
**Do**:
- Implement user stories from `prd.md`
- Check off completed stories: `- [x] US-XX`
- Log completed work in `changelog.md` with date
- Record new decisions in `decisions.md` as they come up
- Write deploy info to `deploy.md` when relevant

**Transition to `check`**: when all user stories in `prd.md` are checked off, or at natural milestones.

### check

Verify the work. Review quality, test results, and deployment.

**Read**: `index.md`, `changelog.md`, `decisions.md`, `deploy.md`
**Do**:
- Run `/brain-review` on the project
- Verify acceptance criteria from `prd.md`
- Check deploy works per `deploy.md`
- Identify issues, gaps, or regressions
- Update `index.md` progress section

**Transition to `learn`**: when review is complete and issues are logged.

### learn

Extract knowledge. What worked, what didn't, what to change.

**Read**: `changelog.md`, `decisions.md`, `learnings/patterns.md`, `learnings/troubleshooting.md`
**Do**:
- Extract reusable patterns -> `/save-learning`
- Log fixes and workarounds -> `/save-troubleshoot`
- Update or retract decisions that didn't hold up
- Move project-specific insights to `learnings/` if broadly applicable

**Transition to `plan`**: to start the next iteration. Or set `status: done` if the project is complete.

## Phase in frontmatter

```yaml
---
status: active
phase: plan
---
```

Valid values: `plan`, `build`, `check`, `learn`

Agents must read `system/lifecycle.md` when they encounter a `phase:` field to understand what to do.

## Cycle flow

```
plan -> build -> check -> learn -> plan (next iteration)
                                -> done (project complete)
```

A project can cycle multiple times. Each cycle typically corresponds to a feature, milestone, or sprint.

## Rules

- Only the agent or user should advance the phase -- never skip phases
- Phase transitions should be logged in `changelog.md`
- A project without `phase:` defaults to `plan`
- `status: done` overrides `phase` -- no further lifecycle actions needed
