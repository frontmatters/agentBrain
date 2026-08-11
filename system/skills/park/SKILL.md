---
name: park
description: Park work-in-progress in agentBrain so a later session can reliably resume without rediscovery. Saves project status via /project-update, discovered insights via /save-learning per insight, and ends with a formatted unpark-prompt that can be pasted into a new session. Triggers - "park this", "save this session", "park this project", "checkpoint session", "save for later resuming", "create handover document", "I need to stop here, save it".
related: [unpark, list-parks, relevant]
---

# park — session handover in agentBrain

Park an active session so a future session (same or different agent, same or
different model) can pick up exactly where you left off.

## When to use

- Work is functionally complete or blocked but not yet "done".
- There are open decisions, fixes, or follow-up steps that must not be forgotten.
- During the session, non-obvious technical details were discovered that will
  also be valuable in other projects.
- The user explicitly says: park, save, checkpoint, handover, "continue later".

## Do not use for

- Short trivial tasks without an open end (e.g. "rename this variable").
- Work that can actually be finished in this session — finish it instead.
- Private info / secrets — those do not belong in agentBrain.

## Steps (follow in this order)

### 1. Gather the facts of this session

Before writing anything, explicitly for yourself:

- **Project name**: ask the user if unclear, or derive from context. Kebab-case.
- **Status**: `active`, `paused`, `blocked`, `done`. Default for /park is `paused`.
- **What is done**: list of concrete deliverables that now work.
- **What is open**: open decisions, identified fixes, external blockers,
  review findings that have not yet been resolved.
- **Insights found**: **ALL** non-obvious technical discoveries from this
  session — edge cases, workarounds, design trade-offs, generic patterns,
  process insights that will also be valid in another project. Sources to
  walk through systematically:
  - Every `★ Insight` block in the chat (without exception — even the "small" ones).
  - Every bug you resolved (the root cause is often a learning).
  - Every review finding you classified — especially ✅ AGREE produces a
    reusable rule.
  - Every "I expected X but it was Y" moment.
  - Every time you had to adjust a spec assumption due to reality.

  Filter for "too trivial" later — first collect everything, then decide.
  When in doubt: save it. A learning nobody ever rereads is cheaper than a
  learning that should have existed but does not.

### 2. Create/update the project document via /project-update

Invoke the `/project-update` skill with the project name. End result is
`~/agentBrain/local/projects/<projectname>/index.md` with:

- Frontmatter: `status`, `priority`, tags including `paused` if status=paused.
- `## Goal` — what this project does and why.
- `## Status (stopped on YYYY-MM-DD)` — one-paragraph summary.
- `## Setup` — table with paths to artifacts, key commands.
- `## Progress` — chronological milestone log, EACH with a date.
- `## Backlog — Unpark instructions` — **this is the heart of /park**:
  - Concrete fix steps numbered, with line indicators where applicable,
    and expected outcome per step.
  - Table of open findings with classification (see below).
  - Optionally: open issues from SPEC that are non-blocking.
- `## Related` — `[[wiki-links]]` to learnings and related projects.
- `## Unpark Prompt` — **persisted unpark prompt** so future sessions can
  copy-paste it directly from the project-doc instead of relying on the
  chat output of the original /park session. Three variants (Standard,
  One-liner, Cross-agent) — same content as Step 4 below.

**Classification of open findings** (from peer-review or audit):

| Symbol | Meaning |
|---|---|
| ✅ AGREE | Reviewer is right, apply fix |
| ❌ FALSE POSITIVE | Reviewer wrong, document evidence |
| ⚠️ DEFER | Valid but lower priority |
| ❌ DISAGREE | Deliberate design choice or trade-off |
| 🔄 NUANCE | Valid but rephrasing needed |

Tally at the bottom: counts per category.

### 3. Save insights as separate learnings via /save-learning

For **every** non-obvious insight a separate call to `/save-learning`.
Do not bundle them in the project document — insights must be cross-project
findable via tags and wiki-links.

Conventions:

- One insight per file (`local/learnings/<slug>.md`).
- File created via `bash ~/agentBrain/scripts/new-note.sh learning local/learnings/<slug> "<title>"` for correct UUID5 + frontmatter.
- Tags are multi-dimensional: project name, topic, tools.
- Structure per learning: `## Insight`, `## Why this matters`,
  `## Fix pattern` or `## How to apply`, `## How discovered`,
  `## Related`.
- Always cross-link back to the project document via `[[<projectname>]]`.
- Check existing learnings with `grep -ril` before creating a new one —
  if there is overlap, **update** instead of duplicating.

### 4. Append the unpark prompt to the project document AND show it

Two outputs in this step:

**(A) Append `## Unpark Prompt` section to `index.md`** — this is mandatory.
Without it, the prompt becomes a wegwerp-artefact of the original /park
chat session. With it, anyone (incl. future-you, weeks later) can find
the exact prompt from `/list-parks` → Read the doc.

The section block to append:

```markdown
## Unpark Prompt

> Copy-paste one of these into a new session to resume this work.

### Standard

\`\`\`
Read ~/agentBrain/local/projects/<projectname>/index.md and pick up
the open backlog: [SHORT-ACTION-SUMMARY]. Do not deviate from the
classified findings.
\`\`\`

### One-liner

\`\`\`
Unpark <projectname> via ~/agentBrain/local/projects/<projectname>/index.md — execute the backlog.
\`\`\`

### Cross-agent (other model)

\`\`\`
Read ~/agentBrain/local/projects/<projectname>/index.md carefully.
Execute the "Concrete fix steps" as described, in order. The classified
findings (✅/❌) have already been re-evaluated — address only the
✅ AGREE items.
\`\`\`
```

Replace `<projectname>` with the actual project slug and `[SHORT-ACTION-SUMMARY]`
with 5-10 words describing the main action (e.g. "apply the 3 fixes
and rerun smoke tests").

**(B) Show the Standard variant inline in chat** so the user has it
immediately without re-reading the doc.

### 5. Confirm what has been saved

Brief summary to the user with paths to:

- The project document.
- Each learning file.
- The unpark prompt (show it inline).
- Reminder: next session, run `/list-parks` to see all parked work, or
  `/unpark <name>` to jump straight in.

## Example output

```
Parked:
- Project: ~/agentBrain/local/projects/foo-skill/index.md
- Insights:
  - ~/agentBrain/local/learnings/foo-edge-case.md
  - ~/agentBrain/local/learnings/bar-pattern.md

Unpark prompt:
> Read ~/agentBrain/local/projects/foo-skill/index.md and pick up
> the open backlog: apply the 2 review fixes, run tests, then promote.
```

## Anti-patterns (do not do)

- **Mixing insights into the project document.** Insights belong in
  `local/learnings/` so they are cross-project findable via tags.
- **Vague backlog items.** "Improve the error handling" is not an unpark
  instruction. Instead: "replace line 142 `echo "$path"` with `exit 1
  with diagnostic`".
- **No date on milestones.** Progress entries without a date are worthless
  for re-evaluation.
- **Unpark prompt full of meta-instructions.** The prompt must be
  self-contained, with action verbs, not "continue where we were".
- **Unpark prompt only in chat, not in the project doc.** The chat
  output is wegwerp; the project doc is the durable record. Always
  append the `## Unpark Prompt` section to `index.md`.
- **Overwriting the project document without preserving the old Progress.**
  Append to Progress, replace Status.
- **Using /park for done work.** If it really is done, set status=done in
  `/project-update` and commit; no unpark prompt needed.

## The three-skill loop

| Skill | When | Direction |
|---|---|---|
| `/list-parks` | start of a session, or any time | see — what is parked? |
| `/unpark <name>` | you picked a project from /list-parks | load — pick up the backlog |
| `/park` | end of working session, not done | save — checkpoint + insights |

Mnemonic: **see → load → save.**

## Related

- [[unpark]] — counterpart; load skill for the parked session in a new session
- [[list-parks]] — dashboard of all parked work
- [[project-update]] — underlying skill for project status
- [[save-learning]] — underlying skill for insights
- [[forward:journal]] — session log skill (complementary, not a replacement)
