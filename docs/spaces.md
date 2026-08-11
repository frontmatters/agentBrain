---
date: 2026-07-29
type: system
tags: [docs, spaces, sealing, confidential, workflow]
id: 4424d5f5-f70b-5829-b93f-94dc683a8e02
---

# Spaces — sealed per-owner compartments

A **space** is a sealed compartment of `local/` for one owner — a client or
employer whose work must stay out of both your personal vault sync and any public
artifact. Each space lives at `local/spaces/<slug>/`, is **gitignored from the
personal vault** (`local/.gitignore` → `spaces/`), and is versioned as **its own
nested git repo** pushed to **its own private remote**. This is the canonical
workflow; policy lives in `system/rules.md` (§ Spaces).

> **Routing model:** writes are routed per-write by **context inference**
> (`system/lib/context.sh`), *not* a session mode. The old `.active-space` marker
> and `active-space.sh` are **decommissioned** — force a context with
> `--context <slug>` or `AGENTBRAIN_CONTEXT=<slug>`.

## The paspoort

Each space carries `local/spaces/<slug>/index.md` — the *paspoort*:

| Field | Meaning |
|-------|---------|
| `type: space` | marks it a paspoort |
| `slug` | the space id used on the CLI |
| `space-id` | the space's stable random UUID (its identity) |
| `id` | the path-derived UUID5 (note-schema invariant, validated everywhere) |
| `owner` | the client/employer name (confidential — never reaches public files) |
| `relation` | `client` \| `employer` \| `personal-family` \| … |
| `aliases` | alternate names that also resolve to this space |
| `confidential: true` | always |
| `sync` | remote URL to back up to, or `none` (local-only, no backup) |
| `code-roots` | repos whose CWD auto-routes writes into this space |

## Workflow

### 1. Create — `scripts/new-space.sh`

```sh
scripts/new-space.sh <slug> --owner "<name>" --relation <client|employer|…> \
    [--aliases a,b] [--code-roots ~/Developer/x,~/work/y] [--sync <url|none>]
```

Writes the paspoort with a fresh `space-id` and the correct path-derived `id`.
It does **not** create the nested repo — that happens at seal time (step 4).

### 2. Route writes — context inference

`new-note.sh` / `/save-learning` / `/project-update` auto-route into a space when:

- you run from one of its `code-roots` (inferred), or
- `AGENTBRAIN_CONTEXT=<slug>` is set, or
- you pass `--context <slug>` explicitly.

When context resolves to a space, notes land under `local/spaces/<slug>/…` with a
`space:` field and a path-correct UUID5. Ambiguous signals refuse rather than
guess. Unknown context → the shared vault (default).

### 3. Map — `scripts/build-space-map.sh`

Regenerates `local/.space-map.json` from the paspoorts (slug ↔ aliases ↔
code-roots) — the lookup table context inference and tooling read.

### 4. Seal + back up — `scripts/sync-space.sh <slug>`

Reads the paspoort `sync:` field:

- `sync: none` → local-only, no commit, no remote.
- `sync: <url>` → inits the nested repo (inside the gitignored `spaces/<slug>/`)
  and pushes to **that remote only** — never the personal vault, never public.

Convention: one private repo per space, named `<slug>-space`. Create it
**private** first, then set `sync:` to its URL, then run `sync-space.sh`.

### 5. Boundary guard — `scripts/check-space-boundary.sh`

Runs in `doctor` (public check): fails if a space `owner` name appears in any
public/tracked artifact. This is the seal's leak gate.

### 6. Deliver / restore — `/brain-extract`, `/brain-restore`

`brain-extract --space <slug>` bundles a space into a portable `.brain-package/`
stamped with its `space-id`; `brain-restore` unpacks it back under
`local/spaces/<slug>/` only.

## What the seal does (and doesn't)

- **Protects** the personal-vault sync (spaces never reach it) and default recall
  (off unless scoped), and keeps owner names out of public artifacts.
- **Does not** block explicit access: a direct `brain_read` of a known
  `local/spaces/<slug>/…` path still works; `--space <slug>` opts one space into a
  scoped listing.

## Related

- `system/rules.md` — the Spaces policy (authoritative for the rules)
- `scripts/new-space.sh`, `scripts/sync-space.sh`, `scripts/build-space-map.sh`,
  `scripts/check-space-boundary.sh`, `system/lib/context.sh`
- `/onboard spaces` — interactive walkthrough of this workflow
