---
date: 2026-08-20
type: system
tags: [ratchets, grandfather, discipline, checks, policy]
id: 9a844cd5-3f40-5b8e-add0-70eac9aa5d0b
---

# Ratchets and the grandfather clause

A reusable way to phase in a new quality rule without a mass retrofit. Any check
in agentBrain can adopt this, so a future improvement does not reinvent it.

## The problem it solves

A new content or quality rule applied to the whole vault at once fails on the
entire pre-existing corpus. That blocks commits for work unrelated to the rule
and forces an impractical retrofit of hundreds of old notes. The audit on
2026-08-20 showed this concretely: a full work-note contract applied
retroactively would fail 100 percent of 392 existing work notes.

## The grandfather clause (date based)

A rule carries a cutover date. Each note is judged against it by its frontmatter
`date`:

| Note date | Verdict | Meaning |
|---|---|---|
| `date` >= cutover | **enforce** | born under the rule, must comply (FAIL on miss) |
| `date` < cutover | **warn** | pre-existing, surfaced as visible debt, not blocked |
| no `date` | **exempt** | cannot be placed in time, skipped conservatively |

The result: a rule is strict going forward with near-zero forced retro work.
Retrofit happens opportunistically because the WARN nudges you when you next open
an old note. It is never a hard gate on old notes.

## The primitive

`scripts/lib/grandfather.sh` is the shared helper. A check sources it and calls
`gf_verdict` per item:

```bash
source "$(dirname "$0")/lib/grandfather.sh"
case "$(gf_verdict "$file" "$CUTOVER")" in
  enforce) # apply the rule; a miss is a FAIL
  warn)    # report the miss, do not fail the run
  exempt)  # skip
esac
```

API: `gf_note_date <file>` reads the frontmatter `date`. `gf_is_after <date>
<cutover>` compares ISO dates. `gf_verdict <file> <cutover>` returns
`enforce|warn|exempt`.

## How to phase in a new rule

1. Write the check as usual (mirror `check-learnings-structure.sh`).
2. Source `lib/grandfather.sh` and pick a cutover date (usually today).
3. Split findings into MUST (FAIL only when the verdict is `enforce`) and SHOULD
   (always WARN).
4. Register the rule in the table below.
5. Wire the check into `scripts/checks/doctor.sh`.

## Ratchet variant (count based)

When items have no date, or the rule is about a total that must not grow, use a
**ratchet** instead: record a baseline count and fail only when a change makes it
worse. A common example is a colour-token ratchet that fails only when a commit
adds a new hardcoded colour. Grandfather is date based and per item; ratchet is
count based and global. Pick the one that fits the signal.

## When not to phase in

A rule with zero or few existing violations needs no grandfather clause. Enforce
it hard from the start. Grandfathering is for rules that would otherwise fail a
large existing corpus.

## Active grandfathered rules (registry)

| Rule | Cutover | Tier | Check | Contract |
|---|---|---|---|---|
| work-note content contract | 2026-08-21 | MUST=fail, SHOULD=warn | `scripts/check-work-note-structure.sh` | `system/work-note-contract.md` |

## Related

- `system/work-note-contract.md` — the first consumer of this methodology.
- `scripts/lib/grandfather.sh` — the primitive.
- `scripts/checks/check-learnings-structure.sh` — the content-check template.
