# Repro-Spec — <Module name> (data-only specialization)

> **Template**: `repro-spec-data-only` (specialization of `repro-spec-primitive`)
> **Inherits**: §1, §2, §3, §4, §8 (callers as consumers), §9, §11, §12.
> **Overrides**: §5, §6, §7 — explicitly **"not applicable — pure data"**.
> **Repurposes**: §10 — anchors are **compile-time layout assertions**,
>          not runtime behavior tests.
>
> Use this specialization when the module exposes a value type with no
> methods and no FSM — pure data (struct/enum/constants). The §5-§7
> "not applicable" path is **part of the contract**, not an oversight. Empirical
> validation: `cell.zig` (12-byte extern struct, 9 constants, 7 anchors —
> all compile-time).

---

## 1. Identity

_Inherit from base — see `repro-spec-primitive.md` §1._

For data-only: explicitly name **pure value type** in `Ownership`. Often
stored inline in larger structs; never heap-allocated standalone.
Multiple consumers is the norm — list them in `Caller(s)`.

## 2. Dependencies

_Inherit from base — see `repro-spec-primitive.md` §2._

Pure data-leaf modules often have `None.` as dependencies.

## 3. Public constants

_Inherit from base — see `repro-spec-primitive.md` §3._

Data-only modules often define **flag-sets** or **palette-sentinels**.
**Constant groupings** (G12 fix) is extra valuable here — e.g. "All
`FLAG_*` are power-of-2 covering 8 bits; designed to be OR-combined."

## 4. Public types

_Inherit from base — see `repro-spec-primitive.md` §4._

For data-only, §4 is the **core of the distillate**. Fill it in completely:

- **Memory layout** _(mandatory — G10 fix)_: for data-only this is often
  the ONLY non-trivial detail. `extern struct` / `repr(C)` / `packed`
  determines cross-language ABI and byte layout — a rebuilder that picks a
  regular struct here may break JS/WASM readers or mmap-IPC.
- **Memory footprint**: exact byte count + layout diagram `[char:4][fg:2]
  [bg:2][flags:1][_pad:3] = 12 bytes`. List padding fields explicitly as field
  rows (do not omit them).
- **Ownership constraints**: usually "pure value type; copy semantics OK".

**Associated public declarations** (optional): if the type has `comptime`
or `static` members (e.g. `TypeName.BYTE_SIZE`, `TypeName.DEFAULT`),
put these in a separate table below the main struct.

## 5. Public API

**not applicable — pure data**

_This is not an oversight. Data-only modules expose no methods/functions._
_Manipulation is the caller's responsibility (assign, OR flags, etc.)._

If there ARE 1-2 trivial helpers after all (e.g. a `default()` factory),
move the module to the base `repro-spec-primitive` template — a
true data-only fits in §1-§4 + §8-§12 without §5.

## 6. Invariants

**not applicable — pure data, no runtime invariants**

_The closest thing to an invariant: a default-constructed value represents_
_the "neutral" / "empty" / "blank" state. Document that as a prose note:_
_"Default-constructed `<Type>` represents <semantic role>."_

Compile-time invariants (sizeof, offsetof) belong in §10 as
`compile-time-layout` anchors, not here.

## 7. Algorithms

**not applicable — no logic**

## 8. Caller contracts

_Inherit from base — see `repro-spec-primitive.md` §8._

For data-only modules, §8 is a **consumers table**: who reads/writes
this type, in which context, for what purpose? No trigger conditions (there
are no calls), but usage patterns.

| Caller | Usage | Notes |
|---|---|---|
| `<consumer>` | <how does this caller use the type — as a field, as an array, as a param?> | <ABI/layout implications> |

**Cross-language contract** (specific to data-only with extern/repr(C)
layout): explicitly state that field order, types, and padding
**MUST NOT change** without a coordinated update of all
language sides (source-language source AND consumers in all other languages
AND any consumers of compile-time size-constants).

## 9. Edge cases

_Inherit from base — see `repro-spec-primitive.md` §9._

Data-only edge cases are usually **value-range semantics**: what does
`fg > 256` mean? What if `char == 0` (NUL)? Which flag combinations are
unusual but valid? Document for the rebuilder so it adds no
defensive validation.

## 10. Behaviour anchors _(repurposed: compile-time layout)_

_For data-only modules, anchors are **compile-time layout assertions**,_
_not runtime behavior tests. This is a fundamentally different paradigm —_
_the gate must know that data-only modules may have ONLY `compile-time-layout`_
_anchors (G11 fix)._

**Anchor classification for data-only**:

| Dimension | Required value |
|---|---|
| **Provenance** | `source-extracted` or `synthetic` (as in base) |
| **Anchor type** | **`compile-time-layout` (mandatory for data-only)** |
| **Module scope** | usually `pure-module` |

Typical anchor categories for data-only:

### Anchor <ID> — sizeof check (compile-time-layout, pure-module)

```
Compile-time assertion:
  sizeof(<Type>) == <N>
```

### Anchor <ID> — field offsets (compile-time-layout, pure-module)

```
Compile-time assertions (offset within <Type>):
  offsetof(<field_a>) == <0>
  offsetof(<field_b>) == <4>
  ...
```

### Anchor <ID> — associated constants (compile-time-layout)

```
Compile-time assertions:
  <Type>.BYTE_SIZE == sizeof(<Type>)
  <flag constants have expected bit-patterns>
  (<flag_a> | <flag_b> | ...) == <expected combined mask>
```

### Anchor <ID> — default-construct field values (runtime-but-zero-cost)

```
Setup: v = <Type>{}            # default init
Expected:
  v.<field_a> == <default>
  v.<field_b> == <default>
  ...                          # incl. explicit _pad fields == 0
```

_Pure runtime-behavior anchors (such as "call X, observe Y mutation") do_
_NOT belong in data-only — if they appear, the module is probably not_
_data-only and belongs in `repro-spec-primitive` or `repro-spec-state-machine`._

**Anchor-coverage guideline**: at least sizeof + offsets-of-all-fields +
default-construct + (if constants form a pattern) constant-pattern
check. For cell.zig this amounted to 7 anchors for 24 source lines —
a high ratio but complete.

## 11. Out-of-scope

_Inherit from base — see `repro-spec-primitive.md` §11._

Common for data-only:
- **No constructors/factories** — caller uses `{}` or explicit field init.
- **No methods** — pure data; manipulation via direct field access.
- **No validation** — value ranges not range-checked; caller's responsibility.
- **No serialization** — extern struct IS the serialization contract (zero-copy
  via shared memory / WASM linear memory).
- **No equality/comparison** — caller uses language built-ins on the value type.
- **No interning / flyweight** — every value is a full copy.

## 12. Dependency abbreviations

_Inherit from base — see `repro-spec-primitive.md` §12._

Pure data-leaf modules: usually "not applicable — no imports."

---

## Gate-checks (delta from base)

In addition to the 12 base gate-checks, for the data-only specialization:

13. §5, §6, §7 contain exactly the string "not applicable — pure data" / "not applicable —
    pure data, no runtime invariants" / "not applicable — no logic" (no
    placeholders or half-filled content).
14. §10 anchors have **only** `compile-time-layout` as anchor type
    (G11 — runtime-behavior anchors in data-only = template mismatch,
    the module probably belongs in the base template).
15. §4 Memory layout field is a mandatory header line (G10) — for data-only
    this is a hard-fail when missing.
16. §4 for data-only with `extern`/`repr(C)`/`packed` layout: §8 MUST contain the
    "Cross-language contract" paragraph (warning against field
    re-ordering without coordination).
</content>
