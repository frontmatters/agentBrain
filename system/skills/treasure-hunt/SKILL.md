---
name: treasure-hunt
description: Use when you've found ONE instance of a bug, anti-pattern, API-misuse, magic value, or brand/PII leak and want EVERY sibling instance across a scope — not a one-off fix. Triggers include "find all", "is this everywhere", "audit for X", "this keeps coming up", or "this is a treasure hunt". Invoke the moment a single found instance likely has siblings.
---

# Treasure Hunt

**One instance is a class, not a one-off.** Never fix only what you found.
Characterize the pattern, sweep the scope, inventory EVERY instance, then fix and
leave a re-runnable guard behind. A hunt's output is not a fix — it's a detector.

## When to invoke

- Right after finding a bug/anti-pattern that could recur (empty render, wrong API
  shape, magic value, missing import, dangling ref, brand/PII leak, a11y violation).
- When the user signals it ("find all", "is this everywhere", "treasure hunt", or
  keeps spotting the same class of thing one at a time).

If you catch yourself fixing a second instance of something by hand — stop and hunt.

## Method

1. **Characterize.** From the seed instance, write down the *detectable signature* —
   the invariant that makes something an instance. Be explicit and falsifiable.
   e.g. "a component with a `label` property given direct light-DOM text and no
   default `<slot>` renders empty."

2. **Pick the detection tier** — cheapest that is *reliable for this pattern*:
   - **Static** (ripgrep / ast-grep / grep) — textual patterns: a call shape, an
     import, a token/magic value, a naming convention. Fast, exhaustive, no runtime.
   - **Runtime** (Playwright / a test harness / the app) — *behavioral* patterns a
     static scan can't see: empty render, dropped text, broken layout, a11y
     violations, wrong computed value. Grep misses these — reach for runtime.
   - **Semantic** (a cheap-model agent sweep) — needs judgment: intent, subtle
     misuse, "does this read as brand X". Fan out one agent per sub-area.
   Prefer the lowest tier that actually catches the pattern. When unsure whether a
   static grep is complete, escalate to runtime — the badge-empty bug looked
   grep-able but only a runtime audit caught the composed cases.

3. **Resolve the scope.** Map the logical scope to concrete paths:
   `class`→the symbol's file · `component`→its module + stories/tests ·
   `package`→packages/<x> · `feature`→the modules that touch it · `codebase`→the
   repo · `project`→every repo/dir in the space · `space`→the sealed owner space.
   If unspecified, infer from where the seed lives and state your assumption.

4. **Sweep.** Run the detector across the whole scope. For large scopes, fan out
   **cheap parallel agents** (one per sub-area) and merge. Inventory EVERY hit —
   never sample or stop at the first few. If you must bound coverage, say so.

5. **Report.** A complete, grouped list: signature, each instance with file:line,
   counts, and (if runtime) evidence. No silent partial coverage.

6. **Fix + guard.** Fix all instances (delegate mechanical fixes to cheap agents if
   many). Then make the detector **durable**: commit a re-runnable script / lint /
   test to the repo (e.g. `harness/<pattern>-audit.mjs`) so the class can't regress —
   next time it's a green/red check, not a hunt. Capture the anti-pattern + the
   detector's location via `/save-learning`.

## Output contract

Every hunt produces four things:
1. the characterized signature (one sentence),
2. the complete instance inventory (grouped, with locations),
3. a **durable detector** (script/test/lint committed to the repo),
4. a learning note (the anti-pattern + how to detect it), via `/save-learning`.

## Anti-patterns this skill prevents

- **The treasure hunt itself** — fixing one, waiting for the user to find the next.
- **Silent partial coverage** — a top-N grep presented as "all of them".
- **Non-durable ad-hoc greps** — a one-time search that can't guard against regressions.
- **Wrong tier** — a static grep for a behavioral bug (misses composed/runtime cases).

## Scale

Small scope (one file/component) → do it inline. Large scope (codebase/project) →
fan out cheap agents per sub-area, then a completeness pass ("what area/tier did I
not cover?"). Behavioral patterns → a Playwright/harness sweep over all states.

## Related

- Born from a real design-system engagement: the badge/button empty-component footgun that recurred 3× before this skill existed.
- A concrete detector was built with this method (a slotted-text audit harness).
