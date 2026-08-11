---
date: 2026-07-25
type: system
tags: [skill, treasure-hunt, audit, quality]
id: 5f448d63-7379-59e5-95c7-4f28107cf527
---

# treasure-hunt

Turn one found bug/anti-pattern instance into a complete, durable sweep instead
of a one-off fix.

## Purpose

Prevents "the treasure hunt" anti-pattern: fixing one instance of a recurring
class of bug (empty-render footgun, magic value, API misuse, brand/PII leak)
while siblings remain, only to be asked to fix "the next one" repeatedly.
Characterizes the pattern's detectable signature, sweeps the whole scope at the
right detection tier (static/runtime/semantic), inventories every hit, fixes
them all, and leaves behind a re-runnable detector so the class can't regress.

## Usage

```
/treasure-hunt
```

Invoke the moment a single found instance looks like it could have siblings —
don't wait to be asked "is this everywhere too?".

## Related

- Born from a real design-system engagement: the badge/button empty-component footgun that recurred 3× before this skill existed.
- A concrete detector was built with this method (a slotted-text audit harness).
