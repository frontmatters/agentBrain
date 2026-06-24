# Repro-Spec — <Module name> (data-only specialization)

> **Template**: `repro-spec-data-only` (specialization of `repro-spec-primitive`)
> **Inherits**: §1, §2, §3, §4, §8 (callers as consumers), §9, §11, §12.
> **Overrides**: §5, §6, §7 — explicitly **"n.v.t. — pure data"**.
> **Repurposes**: §10 — anchors are **compile-time layout assertions**,
>          not runtime behavior tests.
>
> Use this specialization when the module exposes a value type with no
> methods and no FSM — pure data (struct/enum/constants). The §5-§7
> "n.v.t." path is **part of the contract**, not an oversight. Empirical
> validation: `cell.zig` (12-byte extern struct, 9 constants, 7 anchors —
> all compile-time).

---

## 1. Identity

_Inherit from base — see `repro-spec-primitive.md` §1._

Voor data-only: noem expliciet **pure value type** in `Ownership`. Vaak
gestockeerd inline in larger structs; never heap-allocated standalone.
Multiple consumers is de norm — som ze op in `Caller(s)`.

## 2. Dependencies

_Inherit from base — see `repro-spec-primitive.md` §2._

Pure data-leaf modules hebben vaak `None.` als dependencies.

## 3. Public constants

_Inherit from base — see `repro-spec-primitive.md` §3._

Data-only modules definiëren vaak **flag-sets** of **palette-sentinels**.
**Constant groupings** (G12 fix) is hier extra waardevol — bv. "All
`FLAG_*` zijn power-of-2 covering 8 bits; designed to be OR-combined."

## 4. Public types

_Inherit from base — see `repro-spec-primitive.md` §4._

Voor data-only is §4 de **kern van de distillaat**. Volledig invullen:

- **Memory layout** _(verplicht — G10 fix)_: voor data-only is dit vaak
  het ENIGE niet-triviale gegeven. `extern struct` / `repr(C)` / `packed`
  bepaalt cross-language ABI en byte-layout — een rebuilder die hier een
  regular struct neemt, breekt mogelijk JS/WASM-readers of mmap-IPC.
- **Memory footprint**: exact byte-count + layout-diagram `[char:4][fg:2]
  [bg:2][flags:1][_pad:3] = 12 bytes`. Padding velden expliciet als field
  rows (niet weglaten).
- **Ownership constraints**: meestal "pure value type; copy semantics OK".

**Associated public declarations** (optioneel): als het type `comptime`
of `static` members heeft (bv. `TypeName.BYTE_SIZE`, `TypeName.DEFAULT`),
deze in een aparte tabel onder de hoofdstruct.

## 5. Public API

**n.v.t. — pure data**

_Dit is geen oversight. Data-only modules exposen geen methods/functies._
_Manipulatie is caller's verantwoordelijkheid (assign, OR flags, etc.)._

Indien er TOCH 1-2 trivial helpers zijn (bv. een `default()` factory),
beweeg de module naar de base `repro-spec-primitive` template — een
echte data-only past in §1-§4 + §8-§12 zonder §5.

## 6. Invariants

**n.v.t. — pure data, no runtime invariants**

_Het dichtst bij een invariant: een default-constructed value representeert_
_de "neutrale" / "lege" / "blank" toestand. Documenteer dat als prose-noot:_
_"Default-constructed `<Type>` represents <semantic role>."_

Compile-time invariants (sizeof, offsetof) horen in §10 als
`compile-time-layout` anchors, niet hier.

## 7. Algorithms

**n.v.t. — no logic**

## 8. Caller contracts

_Inherit from base — see `repro-spec-primitive.md` §8._

Voor data-only modules is §8 een **consumers-tabel**: wie leest/schrijft
dit type, in welke context, voor welk doel? Geen trigger-conditions (er
zijn geen calls), maar usage-patterns.

| Caller | Usage | Notes |
|---|---|---|
| `<consumer>` | <hoe gebruikt deze caller het type — als field, als array, als param?> | <ABI/layout-implicaties> |

**Cross-language contract** (specifiek voor data-only met extern/repr(C)
layout): expliciet vermelden dat field order, types, en padding
**NIET mogen veranderen** zonder gecoördineerde update van alle
language-sides (source-language source AND consumers in alle andere talen
AND any consumers of compile-time size-constants).

## 9. Edge cases

_Inherit from base — see `repro-spec-primitive.md` §9._

Data-only edge cases zijn meestal **value-range semantics**: wat betekent
`fg > 256`? Wat als `char == 0` (NUL)? Welke flag-combinaties zijn
ongebruikelijk maar geldig? Documenteer voor de rebuilder zodat die geen
defensive validation toevoegt.

## 10. Behaviour anchors _(repurposed: compile-time layout)_

_Voor data-only modules zijn anchors **compile-time layout assertions**,_
_niet runtime behavior tests. Dit is een wezenlijk ander paradigma —_
_de gate moet weten dat data-only modules ALLEEN `compile-time-layout`_
_anchors mogen hebben (G11 fix)._

**Anchor classification voor data-only**:

| Dimension | Vereiste waarde |
|---|---|
| **Provenance** | `source-extracted` of `synthetic` (zoals base) |
| **Anchor type** | **`compile-time-layout` (verplicht voor data-only)** |
| **Module scope** | meestal `pure-module` |

Typische anchor-categorieën voor data-only:

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

_Pure runtime-behavior anchors (zoals "call X, observe Y mutation") horen_
_NIET in data-only — als ze opduiken, is de module waarschijnlijk geen_
_data-only en hoort hij in `repro-spec-primitive` of `repro-spec-state-machine`._

**Anchor-coverage richtlijn**: minstens sizeof + offsets-of-all-fields +
default-construct + (indien constants een patroon vormen) constant-pattern
check. Voor cell.zig kwam dat neer op 7 anchors voor 24 source-regels —
hoge ratio maar volledig.

## 11. Out-of-scope

_Inherit from base — see `repro-spec-primitive.md` §11._

Veelvoorkomend voor data-only:
- **No constructors/factories** — caller uses `{}` of explicit field init.
- **No methods** — pure data; manipulation via direct field access.
- **No validation** — value-ranges niet range-checked; caller's responsibility.
- **No serialization** — extern struct IS de serialization contract (zero-copy
  via shared memory / WASM linear memory).
- **No equality/comparison** — caller uses language-built-ins op value type.
- **No interning / flyweight** — every value is a full copy.

## 12. Dependency abbreviations

_Inherit from base — see `repro-spec-primitive.md` §12._

Pure data-leaf modules: meestal "n.v.t. — no imports."

---

## Gate-checks (delta van base)

Naast de 12 base gate-checks, voor data-only specialization:

13. §5, §6, §7 bevatten exact de string "n.v.t. — pure data" / "n.v.t. —
    pure data, no runtime invariants" / "n.v.t. — no logic" (geen
    placeholders of half-ingevulde content).
14. §10 anchors hebben **uitsluitend** `compile-time-layout` als anchor-type
    (G11 — runtime-behavior anchors in data-only = template-mismatch,
    module hoort waarschijnlijk in base template).
15. §4 Memory layout veld is verplicht header-regel (G10) — voor data-only
    is dit hard-fail bij ontbreken.
16. §4 voor data-only met `extern`/`repr(C)`/`packed` layout: §8 MOET de
    "Cross-language contract"-paragraaf bevatten (waarschuwing tegen field
    re-ordering zonder coordinatie).
