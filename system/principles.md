---
date: 2026-08-20
type: system
tags: [principles, discipline, policy, config, grandfather]
id: 053914a7-4ee5-597f-968e-7b11272bf3ea
---

# agentBrain improvement principles

Base principles that every agentBrain improvement is held to. New tooling, checks,
skills and conventions are reviewed against this list. It grows as principles are
made explicit; each entry names the principle, why it holds, and a worked example
from the codebase.

## 1. Mechanism, not values, lives in code

Logic goes in the script; the values it acts on go in an external config the script
reads. You then change what a rule checks, which items it covers or when it starts,
by editing data, never by editing logic.

**Why.** Values in code invite copy-paste, drift and fear of editing. Values in a
data file are diff-able, reviewable and safe to change without touching behaviour.
It also makes a mechanism reusable: a second consumer points at its own config.

**Example.** `scripts/check-work-note-structure.sh` is pure mechanism. The fields it
requires, their tier and their detector regexes live in
`system/work-note-contract.tsv`; the cutover date and scope types live in
`system/ratchets.tsv`. The script never changes to tune the contract.

**Applies to.** Checks, scaffolds, skills, hooks. Any threshold, list, date, regex,
path set or tier is config, not a literal in the logic.

## 2. Phase a new rule in, never retro-break the corpus

A rule that would fail a large existing corpus is introduced with a cutover: items
born on or after it must comply, older items are surfaced as visible debt and fixed
opportunistically. See `system/ratchets.md` for the grandfather clause and
`scripts/lib/grandfather.sh` for the primitive.

**Why.** A retroactive hard rule blocks commits for unrelated work and forces an
impractical mass retrofit. Phasing keeps the rule strict going forward at near-zero
forced retro cost.

**Example.** The work-note contract is grandfathered at 2026-08-21: the 392 existing
work notes are WARN debt, new notes are enforced.

## 3. Discipline is three layers: scaffold, enforce, document

A convention only sticks when the right way is the easy way (a scaffold), the wrong
way is caught (a check), and the rule is written down once (a doc). One layer alone
erodes: a doc nobody reads, a check with no scaffold to satisfy it, a scaffold with
no check to hold it.

**Why.** Knowledge that is not turned into scaffold plus check decays into goodwill.
The work-note "why" gap existed because the discipline framework enforced note
identity (uuid5) but never note content.

**Example.** Work-note contract: scaffold in `scripts/new-note.sh`, check in
`scripts/check-work-note-structure.sh`, doc in `system/work-note-contract.md`.

## 4. Enforce identity, then content

A note must be well-formed (valid id, frontmatter) and well-conceived (states its
problem, its done-definition, its state). The first was enforced from the start; the
second is the content layer that principle 3 builds.

## How to add a principle

When a review surfaces a rule that should govern all future work, add it here with a
name, a why and a codebase example, then reference it from the check or skill that
first applies it. Keep entries short and concrete.

## Related

- `system/ratchets.md` — the phase-in methodology (principle 2).
- `system/work-note-contract.md` — the first content contract (principles 1, 3, 4).
- `system/rules.md` — the canonical public/private and write-location rules.
