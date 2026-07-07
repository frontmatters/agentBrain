---
name: brain-retro
description: >-
  Run a structured retrospective over agentBrain itself: system, extensions, add-ons, backlog, and knowledge hygiene. Use monthly or after major framework changes.
argument-hint: Optional focus, e.g. "monthly", "addons", "extensions", "backlog", or a date window
user-invocable: true
resources:
  - system/rules.md
  - system/skills.md
  - system/lifecycle.md
  - system/addons/
  - system/pi-config/extensions/
  - local/backlog/
  - local/reviews/
  - local/findings/
---

# Brain Retro

Run a private retrospective on agentBrain as if it were a living system: brain, nervous system, and development process.

## When to use

- Monthly maintenance review.
- After significant changes to skills, extensions, add-ons, or automation.
- When the backlog feels noisy or the brain feels smart but cluttered.

## Procedure

1. **Set the scope**
   - Default window: last 30 days.
   - Optional focus: `addons`, `extensions`, `backlog`, `knowledge hygiene`, or `full`.

2. **Inspect the core brain**
   - Read `system/rules.md`, `system/skills.md`, and `system/lifecycle.md`.
   - Summarize what the core does well: boundaries, rituals, architecture, autonomy.

3. **Inspect the nervous system**
   - Inventory `system/pi-config/extensions/`.
   - Group extensions by role: sensing, memory, safety, workflow, UI, providers.
   - Note missing reflexes, duplicate reflexes, or fragile coupling.

4. **Inspect specialized regions / add-ons**
   - Read `system/addons/README.md` and list registered add-ons.
   - Run `bash scripts/addons.sh status` and `bash scripts/addons.sh check`.
   - Separate healthy enabled add-ons from available-but-unused experiments.

5. **Inspect memory hygiene and quality signals**
   - Run `bash scripts/check-brain-review.sh` or `/brain-review`.
   - Prefer clustering warnings by pattern instead of dumping raw output.
   - Focus on duplicates, stale notes, dead links, generated-noise, and weak signal-to-noise ratio.

6. **Inspect the development backlog**
   - Review `local/backlog/` titles and the most relevant current design notes.
   - Identify overlap, abandoned ideas, repeated plans, and the top 3 active bets.

7. **Make the analogy explicit**
   - Map findings to:
     - `system/` = cortex / executive function
     - `local/` = memory
     - extensions = nervous system / reflexes
     - add-ons = specialized regions or prosthetics
     - checks/reviews = immune system
     - backlog = future plasticity / planned evolution

8. **Write a private retro report**
   - Save to `local/reviews/brain-retro-YYYYMMDD.md` unless the user asks for chat-only output.
   - Include frontmatter:
     ```yaml
     ---
     date: YYYY-MM-DD
     type: review
     tags: [brain-retro, retrospective, agentbrain]
     source: session
     id: <UUID5>
     ---
     ```
   - Generate UUID5 with `scripts/uuid5-gen.sh "local/reviews/brain-retro-YYYYMMDD"`.

9. **Recommend action**
   - End with:
     - what we do well
     - what must improve
     - what to stop doing
     - top 3 next actions
     - whether a recurring skill, extension, or scheduler should be added

## Output outline

```markdown
# Brain Retro — YYYY-MM-DD

## Scope

- Window:
- Focus:
- Sources:

## System Analogy

- Cortex / executive:
- Memory:
- Nervous system:
- Specialized regions:
- Immune system:
- Plasticity / backlog:

## What Works Well

- ...

## What Hurts

- ...

## What Should Improve Next

1. ...
2. ...
3. ...

## Automation Opportunities

- Skill candidates:
- Extension or scheduler candidates:

## Related

- [[brain-review]]
- [[brain-insights]]
```

## Pitfalls

- Do not paste thousands of warnings into the final report; summarize patterns.
- Do not confuse framework health with knowledge health.
- Do not treat every backlog note as active strategy.
- Keep the report private under `local/` because it reflects real usage and priorities.

## Verification

- The retro cites concrete evidence from rules, extensions, add-ons, checks, and backlog notes.
- The report ends with a small action list, not only observations.
- If peer review is available, request a second-opinion review before treating the retro as final.

## References

- `system/skills/brain-review/SKILL.md`
- `system/skills/brain-insights/SKILL.md`
- `system/addons/README.md`
- `system/pi-config/extensions/extensions.md`
