---
name: runbook
description: >
  Author a step-by-step runbook for a multi-stage operation: a pipeline where
  each stage has commands, verifiable gates, and a recovery path. Use when the
  user wants a runbook, ops-doc, playbook, "how do I run X", a deploy pipeline,
  an incident playbook, a checklist-with-commands, or any imperative guide
  where the reader is going to actually run commands. NOT for descriptive
  explainers (use /explainer or /deep-dive) and NOT for one-off scripts
  (write the script instead). The output is a markdown file in the repo or
  agentBrain, no visual rendering. Triggers: "runbook", "playbook", "ops-doc",
  "incident playbook", "deploy pipeline", "stap-voor-stap", "how do I run X
  end-to-end", "make it runnable".
---

# runbook — imperative, gated, recoverable

A runbook is not a tutorial and not a script. It is a **read-while-you-run**
document: the reader is at the keyboard, copying commands, hitting gates, and
needs to know what to do when a gate fails. Three properties make a runbook
actually useful in that setting; everything else is style:

1. **Imperative.** Sentences are commands the reader will execute, not
   observations about a system. Verbs lead: "Run `…`", "Check `…`", "If `…`",
   "Commit and push". A descriptive paragraph belongs in an explainer or a
   design doc, not here.
2. **Gated.** Every stage has an explicit green/red gate the reader can run
   to know whether they may proceed. A gate is a single shell command (or 2–3
   chained ones) plus a clear pass/fail rule the reader can evaluate in their
   head from the output. No gate = no runbook, just a wish list.
3. **Recoverable.** For each gate that can fail, the runbook says *what to do
   if it fails*. Not "investigate" — a concrete rollback command, a known
   cause, or an explicit "stop, do not proceed, hand off to <role>". A
   runbook without a failure path is a trap.

## When to use, when not to

Use when:

- The reader will **execute** the steps (not just read them to learn).
- There are multiple stages with dependencies (stage B needs stage A green).
- Failures have **known** causes (so a recovery can be written).
- The procedure is repeated or handoff-able (runbook for the next agent, not
  one-shot tribal knowledge).

Do **not** use when:

- The output is a description of how something works → `/deep-dive` or
  `/explainer` instead. Runbooks are imperative, not narrative.
- The output is a single shell script → write the script with comments.
  Runbooks are for **judgment-laden** sequences, not pure automation.
- The procedure is one-shot and unrepeatable → a chat transcript is fine.

## The output format

A runbook has a fixed skeleton — keep it, it makes runbooks skimmable under
pressure:

```markdown
# Runbook: <one-line name>

**Purpose.** <one sentence: what this runbook achieves>
**Audience.** <who will run it>
**Preconditions.** <state the world must be in before starting>
**Estimated time.** <how long, honest>
**Failure mode.** <what to do if unrecoverable — usually "stop, page <role>">

## Stage 1 — <name>

**Goal.** <what this stage produces when green>
**Commands.**
\`\`\`bash
<exact command 1>
<exact command 2>
\`\`\`
**Gate.**
\`\`\`bash
<single command or short chain that proves green>
\`\`\`
→ expected: <one line, copy-paste-able pattern the reader can match>
**Recovery if red.**
- If <symptom>: <exact command or sequence to recover>.
- If <other symptom>: <different recovery>.
- If neither matches: **STOP. Hand off to <role> with the failing gate output.**

## Stage 2 — <name>
...
```

## The five-question check per stage

Before a stage goes in, run the same What/Why/Where/How/When loop the
`deep-dive` skill uses — but applied to the **stage** (not the underlying
claim). For each stage:

- **What** — what artefact does this stage produce? Name it concretely
  (a container running, a file at path X with size Y, a row in table Z with
  value V). "It works" is not an artefact.
- **Why** — why is this stage necessary? If you delete it, what breaks?
  Stages without a why are cargo-cult; cut them.
- **Where** — exact paths, hosts, ports, env vars. Vague location ("the
  server") makes the gate ambiguous.
- **How** — the actual commands. Tested on the real system if possible; if
  not, mark with `(unverified — needs validation pass)`.
- **When** — what must be true before this stage starts, and what may not
  happen until it ends. Includes ordering constraints ("never run stage N+1
  while stage N is red").

If any answer is vague, the stage is too vague — fix it before writing.

## Source-of-truth rule

A runbook must be **executable as-written** on the system it describes. So:

- **Cite real paths.** Not "the deploy script" — give the path
  (`scripts/deploy-hetzner-multi.sh`) and the SHA it was tested against.
- **Quote real commands.** Don't paraphrase `docker compose` invocations;
  copy them from the script or the shell history that worked.
- **Mark drift.** If the system has moved since the runbook was written,
  put a "Drift check" stage **first** that confirms paths/versions still
  match. The cost is one extra stage; the benefit is a runbook you can trust.
- **Re-test on every change.** When the system changes, re-run the runbook
  end-to-end on a non-prod equivalent, or at minimum run each gate and
  confirm the expected pattern still appears in the output. Update the
  runbook **in the same commit** as the change that broke it, with a
  "Re-tested: <date>, against <sha>" footer.

## Relationship to other skills

- **`/deep-dive` / `/explainer`** produce *narrative* output (visual explainer
  with diagrams). They explain *why* something is the way it is. A runbook
  explains *what to type*.
- A runbook can **reference** a deep-dive ("For the architecture overview see
  `28-develop-deploy-workflow-deepdive`") but should not duplicate it. Each
  artefact has one job.
- A runbook is **not** a substitute for a deploy script. The script does the
  thing; the runbook is what the human (or agent) reads while invoking the
  script. Often the runbook's "Commands" section is `bash path/to/script.sh
  <args>` plus gates that verify the script's effect.

## Storage

Runbooks live **next to the system they describe**. Two valid homes, pick the
one the next reader will look first:

- **In the repo** (`docs/operations/<topic>/runbook.md`) — when the runbook
  ships with the codebase and any agent that opens the repo should find it.
  Link from `INDEX.md` so it surfaces in the state-snapshot.
- **In agentBrain** (`vault/spaces/<space>/projects/<project>/runbook.md`) —
  when the runbook is mostly about an external system (a vendor, a managed
  service) or when it is sensitive and should not ship with the open repo.
  Link from the project index.

Default: **repo**, because that is where the next agent opens a shell.

## Validation

Before declaring a runbook done, run **three** sanity checks:

1. **Gate dry-run.** Take each gate command, run it on a system that *should*
   be in the pre-run state. Does the output match the expected pattern?
   (If it doesn't, your expected pattern is wrong or the system has drifted.)
2. **Recovery dry-run.** Take each recovery path, simulate the failure
   (best-effort — e.g., point at a wrong port), and confirm the recovery
   actually restores green. If you can't simulate the failure, mark the
   recovery as "(untested — needs incident drill)".
3. **End-to-end dry-run on a non-prod.** Best case: spin up an equivalent
   non-prod system (a throwaway VM, a Colima cluster, a fresh staging
   tenant) and execute the runbook top to bottom. If green, the runbook is
   shippable. If red, the runbook lied — fix it before publishing.

## Measurements & limits — what every runbook should declare

A runbook that says "this will work" without saying **how big** the
things are, **how long** each stage takes, or **where the first
bottleneck sits** is incomplete. The reader will discover these in the
worst possible moment — during an incident, when "stage 3 takes ~1
minute" turns out to be "stage 3 takes 20 minutes because disk is
full". Three things every runbook must state, ideally measured, not
estimated:

1. **Sizes.** How big is the artifact at each stage? Image sizes,
   database sizes, log volumes, secret counts. Not "small" — a number
   in MB/GB. The reader needs to know if a "copy step" will fit on the
   disk they're about to run it on.

2. **Durations.** How long does each stage actually take? Not "fast" —
   seconds or minutes, **with the conditions** (cold cache vs warm
   cache, fresh install vs patch). A table per stage with a "korter /
   langer" column lets the reader extrapolate their own scenario
   without re-measuring.

3. **Limits.** Where is the first bottleneck? "5+ tenants" or "50+
   dossiers/day" or "10 GB uploads" — whichever is most likely to bite
   first. The reader doesn't need to know the second or third
   bottleneck; they need the **first** so they can plan capacity before
   the runbook starts failing in production.

### How to measure (don't estimate)

- **Sizes:** query the system directly. `docker system df`,
  `du -sh`, `wc -c`, `SELECT pg_size_pretty(pg_database_size('x'))`.
  Not "small", not "large" — a number.
- **Durations:** `time <command>` or a wrapper that logs timestamps.
  Run on the actual hardware the runbook targets (a `time` op een
  MacBook zegt weinig over een time op een Synology met 5% CPU).
- **Limits:** extrapolate from current load. "We have 18 containers on
  8 GB; we can probably do 30 before OOM" is honest. "We can do 1000"
  is guessing.

### Where to put the numbers

In the **frontmatter** of the runbook (the `Estimated time` line and a
new `Capacity` block) so the reader sees them **before** they start
running commands. A table is better than prose — the reader scans the
table, doesn't read the paragraph. If a number changes materially,
update the runbook in the same commit as the change that moved it.

### When not to measure

If the system genuinely doesn't exist yet (greenfield, first deploy of
a new service), say so explicitly: "sizes unknown; first deploy
will establish baseline". That's better than guessing, and the reader
will replace it with the real number after the first run. Mark the
spot — don't leave it as a TODO forever.

## Trigger phrases

- "runbook", "playbook", "ops-doc", "incident playbook"
- "deploy pipeline", "stap-voor-stap", "step-by-step ops"
- "how do I run X end-to-end", "make it runnable", "give me the commands"
- After `/deep-dive` if the user then says "now make it a checklist" or "give
  me the actual commands to run" — pivot to runbook format, reuse the
  evidence the deep-dive gathered.
