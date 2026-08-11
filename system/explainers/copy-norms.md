---
date: 2026-07-28
type: reference
tags: [explainers, copy, writing, norms, ste100]
id: 5d7b8d4d-4da4-5a52-b461-f946fae6c4b8
---

# Explainer copy norms: a writing system, not a blacklist

Derived from ASD-STE100 (Simplified Technical English). The principle: banned
words move slop around; a small set of mechanical, self-verifiable rules
removes it. Apply these to all visible copy in explainers (headings, prose,
cards, callouts, table cells). Code blocks, commands and quoted output are
exempt.

## The rules

Check each sentence against these before rendering:

1. **Active voice.** The actor is the subject: "the gate strips pre-blocks",
   not "the pre-blocks are stripped".
2. **One instruction per sentence, max 25 words.** Longer means split.
3. **One meaning per term.** Pick one name per concept and reuse it verbatim;
   the glossary term is the body term. Never alternate synonyms for variety.
4. **Verbs do the work.** "Checks / rejects / renders", not noun chains like
   "performs validation of".
5. **Concrete over qualitative.** Numbers, paths, commands, dates. Never
   "fast", "robust" or "properly" without the measurable fact behind it.
6. **Standard punctuation only.** Comma, period, colon. No em-dash and no
   double hyphen in copy (`check-explainers.sh` enforces this mechanically).
7. **Present tense for behaviour, imperative for instructions.** "The daemon
   serves"; "run", "check".
8. **No filler.** Drop "in order to", "it should be noted", "basically",
   "simply", and intensifiers such as "very".
9. **Expand every abbreviation** on first use, or define it in the glossary.
10. **Paragraphs of six sentences or fewer.** Longer means split by topic.

## Dutch (Nederlands)

The ten rules apply to Dutch copy unchanged; only the language-specific
details differ:

- **Rule 1, active voice**: avoid the lijdende vorm with "worden" ("de gate
  verwijdert pre-blokken", not "pre-blokken worden verwijderd").
- **Rule 2 extra**: avoid tangconstructies; keep verb and object close
  together instead of nesting clauses between them.
- **Rule 3**: technical terms and code identifiers stay in English (daemon,
  import map, commit); do not translate them, and do not alternate between a
  Dutch and English name for the same concept.
- **Rule 8, Dutch filler**: drop "eigenlijk", "gewoon", "in principe",
  "zoals eerder vermeld", "het is belangrijk om te weten dat".

The mechanical checks (rule 6 punctuation, rule 2 sentence length) are
character- and word-count based, so `check-explainers.sh` covers Dutch
explainers without changes.

## Scope

These rules improve form, not substance. They fit technical explainers,
runbooks and reference pages. Do not apply them to quoted material or to
deliberately narrative passages; say so explicitly when a section opts out.

## Enforcement

`scripts/check-explainers.sh` covers rule 6 as a hard FAIL and reports rule 2
outliers as a WARN over the rendered HTML. The other rules are self-checks
for the author (human or model): each one is verifiable by re-reading a
single sentence in isolation, which is what makes the system enforceable.

Source: learning `3897bbda` ("The cure for AI slop is a 1986 aircraft
manual"), 2026-07-28.
