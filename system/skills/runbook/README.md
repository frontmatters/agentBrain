---
date: 2026-08-17
type: system
tags: [skill, runbook, ops, deploy, playbook]
id: 56a60059-4698-5fe9-b577-720a0f8c8390
---

# runbook

Author a step-by-step runbook: imperative commands, verifiable gates, explicit
recovery paths.

## Purpose

Runbooks are **read-while-running** docs for the agent (or human) at the
keyboard. They are not narrative — that is the job of `/deep-dive` and
`/brain-explain`. They are not scripts — that is the job of `bash path/to/script.sh`.

Three properties: imperative, gated, recoverable.

## Usage

```
/runbook <topic>
```

The skill produces a markdown file with the runbook skeleton (Purpose,
Audience, Preconditions, Stages with Commands / Gate / Recovery).

## Storage

Default: in the repo at `docs/operations/<topic>/runbook.md`, linked from the
repo's README or docs index. Override per topic if the system is external or sensitive.

## Relationship

- Consumes evidence from `/deep-dive` runs (paths, commands, gates already
  verified).
- Sibling of `/deep-dive` (narrative) and `/brain-explain` (visual rendering).
- Reference target from `/park` handover docs and `/unpark` resumes — the
  runbook is what the next agent should execute.

## Validation

Three checks before publishing:

1. Gate dry-run on a system in pre-run state.
2. Recovery dry-run (simulate failure, confirm recovery restores green).
3. End-to-end dry-run on non-prod.
