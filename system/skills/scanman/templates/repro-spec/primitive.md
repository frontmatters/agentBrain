# Repro-Spec — <Module name>

> **Template**: `repro-spec-primitive` (base, all primitives inherit this shape)
> **Scanman mode**: `reproduction-spec`
> **Spec version**: v0.6
>
> Reproduction-spec distillate. Goal: enable a blind rebuilder to
> reimplement this module in any systems language without consulting the
> original source, with semantic equivalence verified by §10 anchors.
>
> **Discipline requirement**: this distillate must contain everything required for
> `build + test` of the module, excluding language-specific project setup
> (build systems, package managers — those live in an optional
> language-pack, see SKILL_ADDENDUM §"Future: language packs").

---

## 1. Identity

_Who is this, where does it live, who calls it?_

- **Module name**: `<canonical name>`
- **File**: `<repo-relative path>`
- **Role**: 1-2 sentences — what does this module do and why does it exist?
- **Caller(s)**: who calls this? (one line per caller is OK)
- **Ownership**: heap / static / stack / module-level var / embedded by value
  in caller? The lifetime owner must be explicit.

## 2. Dependencies

_Table: `Imported from | What is used | Value / Type | Why`._
_**Mandatory** (G1 fix): for every imported constant or type alias, name the_
_concrete **value** or **shape**, not just the name. Otherwise the_
_rebuilder must chase transitively through the other distillates._

| Imported from | What is used | Value / Type | Why |
|---|---|---|---|
| `<module>.<ext>` | `<symbol>` | `<u32 = 256>` or `<struct {...}>` | <reason this module needs it> |

If there are no dependencies: explicitly write **"None — self-contained module."**

## 3. Public constants

_Table: `Name | Type | Value | Purpose`. **Mandatory** (G1 fix): for_
_every constant, name the value, not just the name. No_
_`defined elsewhere` — if the constant is needed to build the module,_
_the value belongs here._

| Name | Type | Value | Purpose |
|---|---|---|---|
| `<NAME>` | `<type>` | `<literal>` | <one-line purpose> |

**Constant groupings** _(optional, G12 fix)_: if multiple constants share a
semantic pattern (bitset, enum-like indices, power-of-2 sequence),
name that below the table. Example: "All `FLAG_*` are power-of-2
covering 8 bits — designed to be OR-combined."

## 4. Public types

_One sub-section per type. Mandatory fields under each type header:_
_**Memory layout** (G10 fix — mandatory, not a sub-bullet), **Memory footprint**,_
_**Ownership constraints**._

### `<TypeName>`

One sentence: what does this type represent?

**Memory layout** _(mandatory — G10 fix)_: `<regular | extern | packed | repr(C) | repr(packed)>`.
Justify: why this layout? (cross-language ABI? padding control?
in-place reinterpret?). For data-only modules this is often the ONLY
non-trivial detail.

**Memory footprint**: `<concrete byte-estimate>` — for non-trivial
structs. Give the sum (`[char:4][fg:2][bg:2][flags:1][_pad:3] = 12 bytes`).

**Ownership constraints**: e.g. "never on stack — designed for static/heap
only", "fits on stack (~564 bytes), embed-by-value safe", "pure value type;
copy semantics OK".

| Field | Type | Default | Notes |
|---|---|---|---|
| `<field>` | `<type>` | `<default>` or `"no default — caller must set"` | <constraints / range / undefined-when-not-set> |

_Every field MUST have a default OR explicitly "no default — caller must set"_
_(gate-check)._

## 5. Public API

_One sub-section per function with all the fields below. Do not skip any field_
_— if something is "none", write "not applicable"._

### `<TypeName>.<methodName>(<args>) <return-type>`

- **Signature**: `<full signature with type annotations in pseudo-syntax>`
- **Args**:
  1. `<name>`: <type + semantics — what does this value represent?>
- **Effect** _(numbered steps — observable mutations)_:
  1. <step 1>
  2. <step 2>
- **Returns**: <type + all possible outcomes, incl. null/optional/error>
- **Pre-conditions** _(what the caller MUST guarantee before the call)_:
  - <condition>
- **Post-conditions** _(what is always true AFTER the call)_:
  - <condition>
- **Lifetime** _(of returned pointers/refs)_: e.g. "valid until next
  mutation (`push` or `reset`); caller must not store across mutations".
  Write "not applicable" for pure-value returns.
- **Post-dispatch state visibility** _(G9 fix — only for state-mutating_
  _APIs)_: which fields may/must the caller read AFTER this call and BEFORE the
  next mutating call? Which fields are stale/undefined outside that
  window? Example: "Caller reads `params[0..param_count]` between
  `.csi_dispatch` return and next `feed()`; module does not proactively
  clear after dispatch."

## 6. Invariants

_Numbered I1..In. Goal: the rebuilder knows which asserts belong in tests +_
_debug builds._

| # | Invariant | When checked | Assertion location _(G2 fix)_ |
|---|---|---|---|
| I1 | <one-sentence invariant> | <after which operation does this remain true?> | <`runtime — inside <fn>` or `compile-time — host-side via @sizeOf check` or `debug-only — caller's test`> |

**Assertion location** is mandatory — avoid "elsewhere" phrasings
(G2 fix). A rebuilder must know exactly where the assert belongs: in the
module itself, in the caller, or as a compile-time check in the host.

## 7. Algorithms

_Pseudocode per non-trivial function. "Non-trivial" = contains conditional_
_branching, modular arithmetic, state transitions, or non-O(1) loops._
_Skip trivial assignments._

**Pseudocode discipline** _(G7 fix — STRICTLY language-agnostic)_:
- Allowed: `if`, `else`, `while`, `for i in 0..n`, `return`, `mod`,
  `switch`, struct-field access with `.`, array index with `[i]`, slice syntax
  `a[lo..hi]`, arithmetic `+ - * /`, comparison `== != < <= > >=`,
  logical `and or not`.
- **FORBIDDEN**: language-specific operators (`*|`, `+|`, `??`, `?.`,
  `try`, `catch` with language semantics), built-in type names (`usize`,
  `u32`, `i64` — use prose: "saturating multiply at u16 max").
- **FORBIDDEN**: import syntax (`@import`, `extern`, `use ::`, `from ... import`).
- For saturating/wrapping arithmetic: write out the semantics explicitly
  ("multiply, saturating at u16 max = 65535") or use `saturating_mul(...)`.

```
<function_name>(<args>):
    <step>
    if <cond>:
        <action>
    return <value>
```

Below each pseudocode block: any inline notes about invariants or
edge behavior that is not evident from the code itself.

## 8. Caller contracts

_**Cross-file synthesis**: per public API function, in which source files_
_and under which condition is it called?_

Table: `Trigger site | Condition | Args passed | Notes`

| Trigger site | Condition | Args passed | Notes |
|---|---|---|---|
| `<file>:<fn>` | <when does this caller fire?> | <what args are passed> | <invariants the caller assumes> |

**Reason**: state-mutating modules have behavior that can only be understood
by knowing WHEN the caller uses them. For a blind rebuilder this is
**essential** for tests (G3 fix — anchors that start cross-module
must be transformable into pure-module calls).

**Post-dispatch contract** _(G9 fix — repeat of §5 at the caller level)_:
which fields does the caller read AFTER receiving the dispatch action AND
BEFORE the next mutating call? When is state stable, when is it
overwritten? Document explicitly to prevent defensive resets in the
rebuilder.

## 9. Edge cases

_Numbered list of explicit edge cases with expected behavior._
_Goal: anti-bloat — the rebuilder need not code defensively for cases_
_that are handled here._

- **<edge case name>**: <input/state> → <expected behavior>. <why_
  this behavior (semantics note)>.
- **empty/null inputs**: ...
- **boundary conditions** (0, max, max+1): ...
- **state-transitions** between pre- and post-conditions: ...
- **silent vs error**: which errors raise errors, which are silently
  swallowed/saturated/dropped?

## 10. Behaviour anchors

_Test specs in language-agnostic pseudo-syntax. Goal: the rebuilder can_
_translate these 1:1 into tests in the target language and get them green._

**Anchor classification** _(mandatory — G5 + G11 fix)_:

| Dimension | Values |
|---|---|
| **Provenance** | `source-extracted` (from `test "..."` blocks in source — high confidence) OR `synthetic` (derived from spec — medium confidence, serves as invariant validation) |
| **Anchor type** | `runtime-behavior` (such as push/getLine) OR `runtime-state-machine` (state + transitions) OR `compile-time-layout` (`sizeof`, `offsetof`, byte-reinterpret) |
| **Module scope** | `pure-module` (no cross-module input needed) OR `depends_on_module=<X>` (cross-module — needs companion distillate or stub) |

_Gate-check_: data-only modules (no §5 API) may only have `compile-time-layout`
anchors. State-machines must have at least 1 anchor per documented
state transition (G8 anchor-coverage hint).

### Anchor <ID> — <short description> (`<provenance>`, `<anchor-type>`, `<module-scope>`)

```
Setup: <initial state — exact field values>
Actions: <ordered calls>
Expected after:
  <field> == <value>
  <field> == <value>
```

**Anchor-coverage guideline** _(G8 fix, soft gate)_: aim for at least
1 anchor per public API function + 1 per documented state-transition +
1 per documented edge case. For modules without source tests (`grep -c
'test "' <file>` == 0): all anchors will be `synthetic` — that is
acceptable provided the coverage guideline is met.

## 11. Out-of-scope

_Explicit list of what this module does **NOT** provide. Goal: anti-bloat —_
_prevents the blind rebuilder from adding defensive code for concerns that_
_are deliberately out of scope._

_Minimum 3 items (gate-check). Common ones:_

- **Concurrency model**: e.g. "single-writer assumed; no locks/atomics".
- **Persistence**: e.g. "no serialization; lives in process memory only".
- **Dynamic resizing**: e.g. "<CAPACITY> is compile-time constant".
- **Allocator**: e.g. "none required; static storage" or "caller-provided".
- **Search / filtering / iteration**: e.g. "opaque storage, not queryable".
- **Error recovery semantics** outside specified paths.

## 12. Dependency abbreviations

_Inline minimal spec of imported types/constants — only what_
_is needed to understand the current module._

**WARNING** _(G13 fix — false-confidence risk)_:
> Abbreviations in §12 are **solely for contextual understanding** of
> the current module. They are **NOT a replacement for the full distillate**
> of the dependency. For a stand-alone rebuild of any dependency:
> consult `DISTILLATE/<dep>.md`. Abbreviations typically miss
> edge fields, defaults, or compile-time constants that are not used in the
> current module — a rebuilder that builds on abbreviations alone
> gets **partial coverage with false confidence**.

Per abbreviated dependency:

```
<layout-keyword> struct <TypeName>:    # link: DISTILLATE/<dep>.md for full spec
    <field>: <type> = <default>
    # ... (only fields this module touches)
    # total size = <N> bytes (full layout check in dep's full distillate)
```

If there are no dependencies: **"not applicable — no imports."**

---

## Gate-checks (summary for scanman-validate)

A distillate passes the v0.6 reproduction-spec gate if:

1. All 12 sections present (or explicit "not applicable" where the specialization
   allows it — see `repro-spec-data-only.md`).
2. §2 every dependency row has the Value/Type column filled (G1).
3. §3 every constant has the Value column filled (G1).
4. §4 every type has a **Memory layout** field as a header line (G10).
5. §4 every field row has a default OR "no default — caller must set".
6. §5 every function has all 7 sub-fields (args/effect/returns/pre/post/
   lifetime/post-dispatch-visibility) filled in.
7. §6 every invariant has the `Assertion location` column filled (G2).
8. §7 pseudocode contains no language-specific operators or types (G7).
9. §8 every caller has a post-dispatch-contract note where applicable (G9).
10. §10 every anchor has provenance + anchor-type + module-scope labels (G5/G11).
11. §11 contains at least 3 explicit out-of-scope items.
12. §12 contains the G13 warning if there are abbreviated dependencies.
</content>
