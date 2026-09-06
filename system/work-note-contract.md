---
date: 2026-08-20
type: system
tags: [work-note, contract, discipline, prince2, kanban, scrum]
id: 44b8c0d5-432c-5b72-85d1-7e1c70e45d24
---

# Work-note content contract

What a work note must contain to be well-conceived, not just well-formed. The
identity layers (uuid5, frontmatter) guarantee a note is valid; this contract
guarantees it states a reason, a done-definition and a state. Derived from
PRINCE2 (continued business justification), Scrum (the "so that" value and the
Definition of Done) and Kanban (explicit workflow state and policies).

Applies to the work types: `backlog`, `project`, `task`, `spec`, `decisions`.
It does not apply to `learning`, `reference`, `device`, `integration`,
`session`, `feedback` (those carry their own structure or none).

## The contract

Two tiers. MUST is blocking for notes born under the rule; SHOULD is always
advisory (WARN). Enforcement is phased in with the grandfather clause, so old
notes are surfaced as debt, not blocked. See `system/ratchets.md`.

### MUST (blocking for notes dated on/after the cutover)

| Field | Where | Framework anchor | Why |
|---|---|---|---|
| Problem / why | body `## Probleem` | PRINCE2 business justification, Scrum "so that" | A work item without a stated problem is a solution looking for a reason. It is also what justifies its priority. |
| Acceptance criteria | body `## Acceptatiecriteria` | Scrum Definition of Done | Without a done-definition, "done" is an opinion. |
| Status | frontmatter `status:` | Kanban workflow state | An item with no column is invisible to flow. |

### SHOULD (always WARN, never blocks)

| Field | Where | Framework anchor |
|---|---|---|
| Owner | frontmatter `owner:` | RACI, PRINCE2 roles |
| Priority / value | frontmatter `priority:` | WSJF, MoSCoW |
| Dependencies | frontmatter `depends_on:` | Kanban, PRINCE2 |
| Risks / assumptions | body `## Risico's` | PRINCE2 risk |

## Per-type reading of the MUST set

- `backlog`, `task`: literal. Problem, acceptance criteria, status.
- `project`: Problem is the reason the project exists; Acceptance is the
  project-level Definition of Done; Status is the lifecycle state.
- `spec`: Problem is the motivation; Acceptance is the success criteria.
- `decisions`: Problem is the decision context; Acceptance is the criteria the
  decision must satisfy (the ADR consequences check).

## Enforcement

`scripts/check-work-note-structure.sh` sources `scripts/lib/grandfather.sh` and
judges each work note against the cutover in `system/ratchets.md` (2026-08-21):

- `enforce` (note dated on/after cutover): a missing MUST field is a FAIL.
- `warn` (older note): every miss is a WARN, the run does not fail.
- `exempt` (no date): skipped.

SHOULD fields are WARN for every note regardless of verdict. The check is wired
into `scripts/checks/doctor.sh`.

## Scaffold

`scripts/new-note.sh` emits the MUST body sections and the frontmatter fields for
the work types, so the right structure is the default. The body headings are
Dutch to match the vault; the check accepts Dutch and English variants.

## Retrofit

`scripts/retrofit-work-notes.sh` lists the WARN backlog (old notes missing MUST
fields) and, per note, inserts the missing stubs on request. Retrofit is
opportunistic, never forced.

## Related

- `system/ratchets.md` — the grandfather methodology and the rule registry.
- `scripts/check-work-note-structure.sh` — the enforcing check.
- `scripts/new-note.sh` — the scaffold (discipline framework Layer 2).
