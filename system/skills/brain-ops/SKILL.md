---
name: brain-ops
description: >-
  Query and scaffold the ITSM-inspired ops-records layer — incident, problem,
  known-error (KEDB), and postmortem notes, CI-anchored via the CMDB. Use when
  something breaks and you want to capture it against the CI it touched, consult
  the known-error database before re-solving, or review a CI's incident history.
  Triggers: "log an incident", "known error", "KEDB", "what broke on <host>",
  "postmortem", "ops record", "brain-ops". Block 2 of the IT-frameworks alignment.
argument-hint: "on <ci> | incidents [--open] | known-errors [--ci <c>] | problems | timeline <ci> | show <slug> | new <kind> <slug>"
user-invocable: true
---

# brain-ops

The ops-records layer: what broke, why, and the fix — the counterpart to
`brain-cmdb` (what exists and how it connects). Records are notes under
`vault/[spaces/<slug>/]ops/{incidents,problems,known-errors,postmortems}/`,
CI-anchored through the stable `ci-id` and space-scoped exactly like `brain-cmdb`.

The full design record is kept in the maintainer's vault, not in this repository.

## Commands

```bash
bin=system/skills/brain-ops/bin/brain-ops
bash "$bin" on <ci>                 # every ops record touching a CI (slug or ci-id)
bash "$bin" incidents [--open]      # incidents, optionally only open
bash "$bin" known-errors [--ci <c>] # the KEDB, optionally per CI — CONSULT before re-solving
bash "$bin" problems                # open/known problems
bash "$bin" timeline <ci>           # chronological incidents + postmortems for a CI
bash "$bin" show <slug>             # one record + its links
bash "$bin" new <kind> <slug>       # scaffold a record (incident|problem|known-error|postmortem)
```

Prefix any command with `--space <slug>` to scope to a client space (else it uses
`AGENTBRAIN_CONTEXT`/`context.sh` inference, like `brain-cmdb`).

## When to use

- **Something breaks** → `new incident <slug>`, link the CI(s) it touched.
- **Before solving a recurring problem** → `known-errors --ci <ci>` (consult the KEDB first).
- **A one-off becomes recurring** → climb the ladder: incident → problem → known-error.
- **Major incident** → `new postmortem <slug>` (timeline / root-cause / action-items).
- **"What has broken on this host/service/project?"** → `on <ci>` or `timeline <ci>`.

## The lifecycle (each step optional, never forced)

```
incident (ci-linked, open) → resolved → problem (root-cause) → known-error (KEDB)
major incident → postmortem
```

## Rules

- **CI link is the join key**: `ci:` is a list of stable ci-ids (rename-proof, from
  block 1.5). Author/read via `brain-cmdb resolve` — you type slugs, the id is stored.
- **Flat per context** — no per-project folders; the `ci:` link carries the association.
- **Privacy**: all ops data is private (`vault/`). A client's records stay sealed in
  that client's space and sync to its own remote — never the personal vault.
- `save-troubleshoot` writes a `type: known-error` record here (one coherent KEDB).
- **`promote`** (anonymized space→personal lift) is deferred — see spec §7.
