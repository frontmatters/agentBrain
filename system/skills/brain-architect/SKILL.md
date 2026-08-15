---
name: brain-architect
description: >
  Full-cycle architecture analysis of an existing system, executable by a
  cheaper model: identify building blocks, map constraints through six fixed
  lenses (egress, data, secrets, identity, compliance, operations), take
  design decisions as decision records with abort-conditions, and keep an
  explicit open-questions ledger. Every claim needs evidence (path/grep/
  command output); a deterministic validate.sh gates delivery. Use when the
  user asks for "brain-architect", "architectuur-analyse", "bouwstenen
  identificeren", "what is needed to run X on Y", "wat is er nodig om X op Y
  te runnen", a hosting/deployment design, a decision record, or an
  architecture dossier for an existing repo. Not for greenfield design (use
  brainstorming) or code distillation (use scanman).
argument-hint: <repo-path or project-slug> [design question] [--peer-review] [--lang en|nl] [--html]
user-invocable: true
resources:
  - templates/00-recon.md
  - templates/01-building-blocks.md
  - templates/02-constraints.md
  - templates/03-decision.md
  - templates/04-open-questions.md
  - scripts/validate.sh
---

# Architect

Produce an evidence-gated architecture dossier for an existing system. The
dossier is one markdown file assembled from the five templates, in this exact
section order: Recon → Building Blocks → Constraints → Decisions → Open
Questions. The `## Decisions` heading itself appears in no template: write it
once yourself, then put one filled decision record (03) per design question
beneath it.

## Hard gates (non-negotiable)

1. **Map first, conclude later.** Phase 0 (Recon) blocks everything: no
   building-block table, no decisions, until the recon table is complete.
2. **Every factual claim carries `evidence:`** — a backticked repo path
   (checked for existence by validate.sh), a grep hit, or command output.
3. **Unknown → `⚠ Open`.** Never write an assumption as a fact. An open
   question is a valid result.
4. **Deliver only after `bash ~/agentBrain/system/skills/brain-architect/scripts/validate.sh <dossier> [repo-root]` exits 0.**
   Presenting with a failing validation is an auto-fail: fix, re-run, repeat.
5. **Fixed tokens are never translated**: section anchors (`## Recon`,
   `## Building Blocks`, `## Constraints`, `## Decisions`, `## Open
   Questions`), lenses (`### Egress`, `### Data & Storage`, `### Secrets`,
   `### Identity & Access`, `### Compliance`, `### Operations`), and markers
   (`evidence:`, `abort-condition:`, `⚠ Open`, `**Option N:**`,
   `**Recommendation:**`, `### Decision:`).
6. **Replace every `<angle-bracket>` placeholder** from the templates and
   delete the instructional HTML comments — a leftover `<path>` fails the
   path-existence check with a confusing message.

## Language

Default prose language is **English** (dossiers are handover material). With
`--lang nl` — or when the user asks for the session language — write the prose
in that language. Tokens stay English per gate 5.

## Workflow

### Phase 0 — Recon [blocks all later phases]

1. `brain_search` the topic first (vary terms). An existing dossier/explainer
   is input, never ignored. Empty search → filesystem fallback per the
   lookup-first protocol.
2. Map the repo with `ls`/`grep` (grep-first per concern) until the table in
   `templates/00-recon.md` is complete: entrypoints, config, data dir, auth,
   egress, build.
3. No access to the repo/path → stop with a clear message. Never produce a
   fantasy analysis.

### Phase 1 — Building Blocks

Fill `templates/01-building-blocks.md`: the mermaid mental model (components +
data flow) and the component table. Name explicitly what is privileged (the
blast radius) and what is delegated to third parties.

### Phase 2 — Constraints

Fill `templates/02-constraints.md`: the egress/zone mermaid diagram, then all
six lenses. Every lens: facts with `evidence:` or an explicit `⚠ Open:` line.

### Phase 3 — Decisions

Write the `## Decisions` heading, then one `templates/03-decision.md` record
per design question the user asked (or that the analysis surfaced). Context →
≥2 options with trade-offs → recommendation → ≥1 `abort-condition:`.

With `--peer-review`: send the draft Decisions section through the
`peer-review` skill and process the verdict before delivery. A negative
verdict → revise the record, or include the disagreement explicitly in the
record. Never silently ignore it.

### Phase 4 — Open Questions

Fill `templates/04-open-questions.md`: collect every `⚠ Open` into the ledger;
each row names who or what can answer it.

### Delivery

1. Determine `<slug>`: reuse the existing `local/projects/` directory for
   this repo if one exists — find it by searching for the repo path or name:
   `grep -rl "<repo-dir-name>" ~/agentBrain/local/projects/*/index.md`
   (the directory whose `index.md` mentions this repo is the slug).
   Only if nothing matches: the kebab-cased repo directory name. Then create the dossier
   note:
   `bash ~/agentBrain/scripts/new-note.sh project local/projects/<slug>/architecture "Architecture — <name>"`
   If `architecture.md` already exists there, skip new-note.sh and update
   the existing note in place (keep the generated `id:` line intact).
   Add one line `repo: <absolute repo path>` to the frontmatter (directly
   under `id:`), and paste the assembled dossier below it.
2. Validate: `bash ~/agentBrain/system/skills/brain-architect/scripts/validate.sh
   ~/agentBrain/local/projects/<slug>/architecture.md` — repeat until it
   prints `OK`.
3. Copy into the target repo: `docs/architecture/<YYYY-MM-DD>-<topic>.md`
   (create the directory if needed), stripping the vault frontmatter from
   the copy (no agentBrain ids in client repos). The vault note is the
   source of truth.
4. With `--html` (or on request): render via the `brain-explain` skill,
   which owns the output path (the dossier already carries the two mermaid
   diagrams; markdown stays the source, never hand-edit the HTML).
5. Report to the user: dossier path (vault + repo copy), validation result,
   the decision recommendations in one line each, and the open questions.

## What this skill is not

- Not greenfield design (use brainstorming → writing-plans).
- Not code distillation/redesign (use scanman).
- Not implementation: it delivers a dossier, not code changes.
