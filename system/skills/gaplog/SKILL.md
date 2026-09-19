---
name: gaplog
description: Start or maintain a gaplog, the register of things that already look built but do not do what they promise. Use when a claim about a running system turns out to be false, or when a project needs somewhere to keep such findings.
argument-hint: Optional project slug or a finding to file
user-invocable: true
related:
  - queue
resources:
  - scripts/new-note.sh
---

# Gaplog

A backlog collects what we intend to build. A **gaplog** collects what **already looks
built but does not do what it promises**. Two registers, not two flavours of one list.

**Announce:** "Filing this in the gaplog / starting a gaplog for <project>."

## Why both exist

**A backlog item is a promise not yet made. A gaplog item is a promise already made and
broken.** Everything follows from that asymmetry:

- **Priority.** A backlog item is prioritised on value and deferring it is free, because
  nobody was told it exists. A gap was prioritised the moment the promise was made; the
  only open question is when it gets honoured, and deferring costs trust daily.
- **Burden of proof.** A gap asserts that something is broken *right now*. That assertion
  must be provable, so evidence is mandatory. A backlog item asserts nothing about the
  present and needs none.
- **How each is found.** A backlog is found by thinking. A gaplog is found by **looking**:
  running the thing and comparing what you see with what was claimed. Nobody ever plans the
  entry "the route the client calls does not exist on the server". That is why a gaplog has
  no other source and is lost the moment it stops being written down.

## The routing test

The hard cases sit on the border, and "is code missing?" is the wrong question.

> **A gap is a broken promise to a user. Missing code is backlog.**

Worked example: a manual ships screenshots that go stale on every UI change, because the
capture set was never a maintained script. Nobody promised a script, so the script is not
the gap. The manual promises to be current and structurally cannot be, so *that* is the
gap, and the script is the backlog item that closes it.

**One direction only.** A gap may spawn a backlog item; a backlog item never spawns a gap.
The gap keeps the reference. Without this rule two lists describe the same work, and it
gets done twice or not at all.

## Starting one

```bash
bash scripts/new-note.sh gaplog vault/projects/<slug>/gaplog "<Project> gaplog"
```

A gaplog lives beside the project it belongs to, so the project note must exist first.
Inside a space, add `--space <slug>` (or let context inference do it from the code-root).
The scaffold ships the reading key, the register and the allocation split; do not redesign
them per project; the columns are the contract.

## Where it lives: one register per level

A gaplog is not a single list. It exists at four levels, and all four are supported:

| Level | Path | Whose promise |
|---|---|---|
| framework | `vault/gaplog` | agentBrain itself, when a mechanism does not do what it claims |
| space | `vault/spaces/<slug>/gaplog` | a client or employer convention that spans their projects |
| project | `vault/projects/<slug>/gaplog` | one product's promises to its users |
| feature | `vault/projects/<slug>/<feature>/gaplog` | a chapter large enough to have its own reader |

A project gaplog needs the project note to exist first; the script says so and refuses,
which is the guard doing its job.

**The placement rule falls straight out of the definition: file the gap at the level of the
promise that was broken.** The screen told a user something untrue, so the gap is the
product's. A framework mechanism claimed to prevent a mistake and did not, so the gap is
the framework's. A convention was agreed once for a whole client and is broken in three of
their projects, so the gap is the space's. You never have to guess, because you can always
name who made the promise.

Two rules keep four registers from becoming four fragments:

1. **A gap lives at exactly one level**: the level at which the promise was made. If the
   promise is per-feature, do not also file it on the project.
2. **Rollup is read-only.** A higher level may list what sits below it; it never copies
   entries upward. A copied row goes stale in one place and gets fixed in the other.

Do not create a level before it has entries. A feature gaplog with two rows belongs in the
project register until the chapter is big enough to have its own reader.

## Every row carries these

| Field | Why it is load-bearing |
|---|---|
| ID | so a human and an agent can name the same finding in one token |
| Where | a gap without a locus is a mood, not a finding |
| State | BROKEN / MISLEADING / UNFINISHED / UNVERIFIED / RESOLVED |
| What | stated as the broken promise, not as a code smell |
| Found by | human or agent. Not for credit: it shows where each party is blind |
| Evidence | file+line, a measurement, or a query. **No row without it** |
| Verified | who checked it, and when |

A report from a person is an **observation, not a diagnosis**. Verify it yourself before
the row claims anything, and say so in the Verified column. An observation from last week
may not reproduce today. A hunch is a legitimate row, but it is `UNVERIFIED` and never
written as fact.

## Allocating the work

A register of thirty findings is not a work queue. Split every entry by **who can close
it**: agent, owner, or outside. That split is what makes unattended work safe.

The honest failure mode: an item filed as *agent* that turns out to need a modelling or
taste decision must be **handed back**, with the options written out, rather than resolved
by guesswork. Handing one back is a result, not a failure.

## Anti-patterns

- **Merging the two registers.** The merged list loses the evidence discipline, which is
  the only reason a gaplog can be trusted enough to act on unattended.
- **A row without evidence.** Then it is a complaint, and complaints do not survive review.
- **Restating someone's report as a finding.** Verify first; record what you checked and when.
- **Counting the list wrong.** Allocation tables repeat IDs; count the register, not the
  allocation.
- **Silently resolving an owner-decision item.** Hand it back with the options instead.

## Related

- `/queue`: once a gap is allocated to the agent, the work itself is queued there.

The principle behind the two registers, the field-by-field contract and how the schema was
arrived at live as a learning in the owner's vault: search the brain for *two registers of
work*. This file is public, so it does not link into private notes.
