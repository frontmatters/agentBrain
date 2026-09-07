---
date: 2026-08-25
type: reference
tags: [addon, goal, agentbrain, agent-agnostic]
status: active
id: 3cf017bf-db0f-5f78-a13b-effbdad33471
---

# goal — agentBrain goal capability

A goal is a **verifiable stop-condition**: an agent works until it is demonstrably met,
then it auto-clears. This addon holds the agent-neutral logic and a portable CLI, so the
same goal system works across agents instead of living in one runtime.

## Layout

- `lib/core.ts` — pure, framework-neutral logic (zero imports): the 5WH SMART gate
  prompt + parser, the grill-me directive, the evaluator prompt + verdict parser, the
  log-entry shape, and the per-context path/slug helpers. Any agent can import it.
- `bin/ab-goal` — an agent-neutral CLI (bun). File-based state, so Claude Code (via
  Bash), cron or a script can hold one goal per context and share the log.
- The **pi extension** (`system/pi-config/extensions/goal.ts`) is the rich consumer:
  the `/goal` command, the `goal_check` tool, the SMART gate with an automated model
  call, the grill-me on a non-verifiable goal, and the resume-recheck hook.

## Shared state and log (local, unsynced)

Both consumers use `~/.agentBrain/goal-logs/<context>/`:

- `goals.jsonl` — append-only history of every `set` and `cleared` (with the outcome).
- `current.json` — the active goal (the CLI's file-based state; pi uses its session).

Local by default (a condition can carry confidential text; keep it off the synced vault).
`GOAL_LOG_DIR` / `GOAL_LOG_PATH` / `GOAL_LOG_CONTEXT` override the location and context.

**Context** partitions the logs per space or project: `GOAL_LOG_CONTEXT` (a space slug)
> the git repo name > `personal`. `sanitizeContext` blocks path traversal.

## CLI

```
ab-goal set <condition>   [--original <raw>] [--context <slug>]   # pass a SMART condition
ab-goal status            [--context <slug>]
ab-goal met [reason]      [--context <slug>]                      # achieved
ab-goal clear [reason]    [--context <slug>]                      # stop early
ab-goal log [n]           [--context <slug>]
```

The CLI holds and logs the goal; the calling agent owns the SMART/verify reasoning (it
is the model). The pi extension automates that reasoning with a model call.

## Tests

`bun test tests/core.test.ts` (pure logic) plus the pi integration test in
`system/pi-config/extensions/tests/goal.integration.test.ts` (wiring + auto-clear +
per-context placement).
