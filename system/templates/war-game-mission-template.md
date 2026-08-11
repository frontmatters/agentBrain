---
date: 2026-07-05
type: reference
tags: [template, wargame, reference, agentbrain]
id: 97018376-6754-5ddc-8be4-6c3873a71ed5
---

# War-Game Mission Template

> Copy this file to `local/projects/<project>/war-games/<mission>.md` and fill it in.
> Method: see `local/learnings/pre-deprecation-wargame-playbook.md` (if present in your vault).

---

## Mission: <title>

**Goal:** what should this wargame produce (no execution, blueprint only)?

**Executor model (post-deprecation):** <e.g. Sonnet 5 / Opus 4.8 / GLM-4.6 / local>

## Mission brief

< concrete context: for whom, which problem, which constraints, ICP, call-to-action, test paths >

## WAR GAME ORDER

You are NOT executing this mission. You are purely wargaming it.
A cheaper executor model (<executor>) will run the brief below.

Fight the mission on paper, move by move. Every move states:
- expected observation (success signal)
- most likely failure + cause + observable signals
- the counter-move

Every fork gets a trigger: IF observe X THEN route A ELSE route B.
End with abort conditions.
Flag assumptions your recon could not resolve → ledger.md.

## Moves (action → reaction → counteraction)

### Move 1: <action>
- **Expected:** <success observation>
- **Most likely failure:** <cause + signal>
- **Counter-move:** <recovery>
- **Forks:**
  - IF <observe> THEN <route A>
  - ELSE <route B>

### Move 2: …

### Move N: …

## 2nd/3rd/4th-order consequences

< what can go wrong a few layers deeper? >

## Abort conditions

- <when does the plan stop? hard blockers>

## Inputs needed (→ ledger.md)

- <variable the user must fill in>

## Success criteria

- <when is this wargame "good enough" to feed to a cheaper model?>

## Tailor for executor model

< specific adjustments for <executor>, based on its system card / docs >
