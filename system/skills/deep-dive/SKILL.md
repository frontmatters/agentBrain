---
name: deep-dive
description: >
  Produce a DEEP tutorial (not a summary one-pager) on a topic, or turn an
  existing explainer/note into one. For every claim it runs a
  What/Why/Where/How/When interrogation loop, hunts down concrete evidence
  (real file paths, commands, code, numbers), flags anything still vague, and
  resolves it before writing — then renders themed HTML by handing off to the
  brain-explain skill. Use this whenever the user wants something thorough,
  step-by-step, "not a one-pager", "go deeper", "make it a real tutorial",
  "explain X properly / in depth", a handbook, masterclass, runbook, or
  training guide — or is dissatisfied that an explainer is "too summary".
  Trigger even if they say "deep-dive", "unpack this", or "prove each claim".
---

# deep-dive — claims interrogated until nothing is vague

A one-pager *asserts*. A deep-dive *proves*. The difference is discipline, not
length: every claim gets pinned down with five questions until a reader could
act on it without guessing. This skill encodes that discipline, then reuses
`brain-explain` for the rendering so you never rebuild a renderer.

## The core move: the 5-question loop per claim

A "claim" is any sentence that tells the reader something is true or should be
done ("add colour roles", "impersonation is the enterprise default", "the
judge passes green cards"). **Summary and counting claims are claims too** —
"five artefacts carry the knowledge", "there are three reasons", "two files
disagree" all promise a specific set. Never make the reader read on to
discover *which* five/three/two: enumerate the members inline, right where the
count is stated, each one named and one-line-characterised. A count without
its members listed is the classic one-pager tease — it asserts a structure it
doesn't show. For **each** claim, before it goes in the document, answer all
five — concretely, not abstractly:

- **What** — restate the claim precisely. What exactly is being asserted or
  asked for? Strip vague words ("better", "properly", "conform"): replace
  them with the specific thing. If you can't, the claim is too fuzzy to keep.
- **Why** — the reasoning and the stakes. Why is this true / worth doing?
  What breaks if you ignore it? A claim without a "why" is dogma; the reader
  can't adapt it to their case.
- **Where** — the concrete locus. Which file, function, line, config key,
  system, or step does this touch? Real paths and anchors, not "in the
  config". If it lives nowhere specific, say why it's still general.
- **How** — the executable detail. Exact steps, commands, code, or the
  worked mechanism. If a reader asked "ok, how?", the answer is already here.
  Show it, don't gesture at it.
- **When** — conditions and ordering. When does this apply, when does it
  NOT, what must happen first/after? Edge cases and exceptions live here.

**Write the five as explicit labels, one per answer** — start each with
`**What.**`, `**Why.**`, `**Where.**`, `**How.**`, `**When.**` (bold, followed
by the answer). brain-explain renders a run of these labels as a definition
list — each label on its own line with its answer beneath — so the loop is
legible instead of a run-on block. Never merge the five into one flowing
paragraph; that is the unreadable form the label style exists to prevent.

If any of the five can't be answered from what you know: **that's a gap, not a
detail to skip.** Investigate it (read the file, run the command, check the
harvest) or, if genuinely unresolved, write it into the document as an
explicit open question — `> ⚠ Open: <what's unknown and how to resolve it>`.
Never paper over a gap with confident vague prose. The whole value of a
deep-dive is that it doesn't leave the reader where a one-pager does.

## Process

1. **Scope the claims.** Either (a) you're given a topic — enumerate the
   claims a thorough treatment must make; or (b) you're deepening an existing
   one-pager/note — read it and extract every claim it makes (each bullet,
   each "do X", each assertion is a claim). List them before writing.

2. **Investigate first, write second.** For a technical topic, this means
   actually reading the code/files and running commands so the Where/How are
   real. Use subagents to parallelize investigation across claims when there
   are many and they're independent. A deep-dive that cites `page-judge.mjs`
   line-for-line beats one that says "the judge checks colours".

3. **Expand each claim into a section** using the loop. A claim becomes a
   short section that a reader can act on: what precisely, why it matters,
   where it lives, how to do it (with the command/code/snippet), when it
   applies. Order sections so earlier ones unblock later ones.

4. **Add the connective tissue** a tutorial needs and a one-pager skips: a
   mental model up front, a worked end-to-end example, a "when NOT to" or
   failure-modes section, and a repeatable ritual/checklist at the end so the
   knowledge is reusable, not one-shot.

5. **Self-check for residual vagueness.** Re-read with fresh eyes: any
   sentence a skeptic could answer "yeah but *how* / *where* / *why*?" is a
   surviving one-pager claim — expand or cut it. Any hedge ("should", "might",
   "in some cases") either gets a concrete condition (the "When") or goes.

6. **Link internal cross-references.** When the document names something it
   describes elsewhere — a role in a summary matrix, a leak referenced from the
   worked example, a term with its own section — make it an in-page anchor
   link: `[Creator](#creator-editor)`. brain-explain gives every heading a slug
   id (lowercased, spaces→`-`), so a reader in a table can jump straight to the
   full treatment instead of hunting. A reference table whose rows are just
   plain text, when each row has a section, is a missed link — wire it.

7. **Render via brain-explain.** Write the note as markdown with brain-explain
   frontmatter (`type: explainer`, a `category`, `theme: clean-flat` unless
   told otherwise) and its shortcodes (`:::cards`, `:::flow`, `:::callout`,
   tables), then invoke the **brain-explain** skill to render themed HTML and
   open it. Do not hand-roll HTML — brain-explain owns rendering and enforces
   the visual norms. Link the note in the explainers MOC.

## What separates a deep-dive from an explainer one-pager

| One-pager | deep-dive |
|---|---|
| States the claim | Proves it (5-question loop) |
| "Add colour roles" | Shows the exact JSON edit, the file, why membership≠permission, the judge line that misses it, when it applies |
| Adjectives ("better", "clean") | Concrete targets and mechanisms |
| Skips gaps silently | Flags gaps as explicit open questions |
| Read once | Has a worked example + a repeatable ritual |

## Structure to reach for (scale to the topic)

- **Part 0 — mental model:** the machine/system in one diagram-in-words, and
  the handful of artefacts every later section touches. Grounds the reader.
- **Diagnose / understand** before prescribing — how to *see* the thing.
- **Body** — one section per claim, expanded via the loop, ordered by
  dependency.
- **Worked example** — the whole method applied end-to-end to one concrete
  case, as a checklist the reader can literally follow.
- **Ritual / checklist** — the repeatable version so it sticks.
- **Appendix** — the reference distilled (file map, commands).
- **Glossary — MANDATORY, always the final section.** Every deep-dive ends
  with a glossary. See the rule below.

## The Glossary is not optional

A deep-dive names things a newcomer won't know — code identifiers
(`resolveRole`, `off()`), file names (`design-constants.json`), domain terms
(`impersonation`, `four-eyes`, `status-only role`), acronyms (RBAC, ADC, SA).
A one-pager assumes you already know them; a deep-dive **defines every one it
uses**, so a reader who lands cold can still follow it.

Rules:
- **Always end with a `## Glossary` section.** No deep-dive is complete
  without it — this is a hard structural requirement, same status as the
  5-question loop.
- Include every term, identifier, file, and acronym the document uses that a
  smart outsider to *this* system wouldn't already know. When in doubt,
  include it — an over-full glossary costs a line; a missing term costs the
  reader the thread.
- Each entry: the term, then a one-sentence plain-language definition **in the
  context of this document** (not a dictionary definition). For a code symbol,
  say what it does and where it lives; for a domain term, what it means here.
- Order alphabetically or by first appearance — whichever helps lookup. A
  table (`| Term | Meaning |`) renders cleanly via brain-explain.
- Build it *from the finished document*: scan the text for every named thing
  and confirm it has an entry. A term used but not defined is the same failure
  as a claim asserted but not proven.

## Notes

- **Write the document in English by default.** Deep-dives are reference
  material meant to be shareable (towards colleagues, enterprise
  conversations), so the note itself is English regardless of the chat
  language — unless the user explicitly asks for another language. The chat
  around it stays in the user's language; only the rendered artifact is
  English by default. This avoids a translate-round after the fact.
- Length serves depth, not the reverse. A deep-dive is long because every
  claim earned its expansion — never padded to look thorough.
- **Copy follows the explainer writing system** (`system/explainers/copy-norms.md`,
  STE-derived): active voice, max 25-word sentences, one term per concept,
  concrete over qualitative, no filler. A checkable system, not a banned-word
  list — self-verify each rule per sentence before rendering.
- Reuse everything: brain-explain for rendering + theme + norms, the vault's
  `new-note.sh` for frontmatter/UUID, subagents for parallel investigation.
- If the user names a theme, pass it through to brain-explain; otherwise
  `clean-flat` (the shipped default) unless the vault config says else.
