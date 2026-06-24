# Repro-Spec — <Module name>

> **Template**: `repro-spec-primitive` (base, all primitives inherit this shape)
> **Scanman mode**: `reproduction-spec`
> **Spec version**: v0.6
>
> Reproduction-spec distillate. Goal: enable a blind rebuilder to
> reimplement this module in any systems language without consulting the
> original source, with semantic equivalence verified by §10 anchors.
>
> **Discipline-eis**: this distillate must contain everything required for
> `build + test` of the module, excluding language-specific project setup
> (build systems, package managers — those live in an optional
> language-pack, see SKILL_ADDENDUM §"Future: language packs").

---

## 1. Identity

_Wie is dit, waar woont het, wie roept het aan?_

- **Module name**: `<canonical name>`
- **File**: `<repo-relative path>`
- **Role**: 1-2 zinnen — wat doet deze module en waarom bestaat hij?
- **Caller(s)**: wie roept dit aan? (één regel per caller is OK)
- **Ownership**: heap / static / stack / module-level var / embedded by value
  in caller? Lifetime-eigenaar moet expliciet zijn.

## 2. Dependencies

_Tabel: `Imported from | What is used | Value / Type | Why`._
_**Verplicht** (G1 fix): bij elke geïmporteerde constant of type-alias de_
_concrete **waarde** of **shape** noemen, niet alleen de naam. Anders_
_moet rebuilder transitive jagen door de overige distillaten._

| Imported from | What is used | Value / Type | Why |
|---|---|---|---|
| `<module>.<ext>` | `<symbol>` | `<u32 = 256>` of `<struct {...}>` | <reason this module needs it> |

Indien geen dependencies: schrijf expliciet **"None — self-contained module."**

## 3. Public constants

_Tabel: `Name | Type | Value | Purpose`. **Verplicht** (G1 fix): bij_
_elke constant de waarde noemen, niet alleen de naam. Geen_
_`defined elsewhere` — als de constant nodig is om de module te bouwen,_
_hoort de waarde hier._

| Name | Type | Value | Purpose |
|---|---|---|---|
| `<NAME>` | `<type>` | `<literal>` | <one-line purpose> |

**Constant groupings** _(optioneel, G12 fix)_: als meerdere constants een
semantisch patroon delen (bitset, enum-like indices, power-of-2 reeks),
benoem dat onder de tabel. Voorbeeld: "All `FLAG_*` zijn power-of-2
covering 8 bits — designed to be OR-combined."

## 4. Public types

_Per type één sub-sectie. Verplichte velden onder elke type-header:_
_**Memory layout** (G10 fix — verplicht, niet sub-bullet), **Memory footprint**,_
_**Ownership constraints**._

### `<TypeName>`

Eén zin: wat representeert dit type?

**Memory layout** _(verplicht — G10 fix)_: `<regular | extern | packed | repr(C) | repr(packed)>`.
Motiveer: waarom deze layout? (cross-language ABI? padding-control?
in-place reinterpret?). Voor data-only modules is dit vaak het ENIGE
niet-triviale gegeven.

**Memory footprint**: `<concrete byte-estimate>` — voor non-trivial
structs. Geef de optelsom (`[char:4][fg:2][bg:2][flags:1][_pad:3] = 12 bytes`).

**Ownership constraints**: e.g. "never on stack — designed for static/heap
only", "fits on stack (~564 bytes), embed-by-value safe", "pure value type;
copy semantics OK".

| Field | Type | Default | Notes |
|---|---|---|---|
| `<field>` | `<type>` | `<default>` of `"no default — caller must set"` | <constraints / range / undefined-when-not-set> |

_Elke field MOET een default OF expliciet "no default — caller must set"_
_hebben (gate-check)._

## 5. Public API

_Per functie één sub-sectie met alle velden hieronder. Sla geen veld_
_over — als iets "geen" is, schrijf "n.v.t."._

### `<TypeName>.<methodName>(<args>) <return-type>`

- **Signature**: `<full signature with type annotations in pseudo-syntax>`
- **Args**:
  1. `<name>`: <type + semantiek — wat representeert deze waarde?>
- **Effect** _(genummerde stappen — observeerbare mutaties)_:
  1. <step 1>
  2. <step 2>
- **Returns**: <type + alle mogelijke uitkomsten, incl. null/optional/error>
- **Pre-conditions** _(wat de caller MOET garanderen vóór de call)_:
  - <condition>
- **Post-conditions** _(wat altijd waar is NA de call)_:
  - <condition>
- **Lifetime** _(van returned pointers/refs)_: e.g. "valid until next
  mutation (`push` or `reset`); caller must not store across mutations".
  Schrijf "n.v.t." voor pure-value returns.
- **Post-dispatch state visibility** _(G9 fix — alleen voor state-mutating_
  _APIs)_: welke velden mag/moet de caller lezen NA deze call en VÓÓR de
  volgende mutating call? Welke velden zijn stale/undefined buiten dat
  window? Voorbeeld: "Caller reads `params[0..param_count]` between
  `.csi_dispatch` return and next `feed()`; module does not proactively
  clear after dispatch."

## 6. Invariants

_Genummerd I1..In. Doel: rebuilder weet welke asserts in tests +_
_debug-builds horen._

| # | Invariant | When checked | Assertion location _(G2 fix)_ |
|---|---|---|---|
| I1 | <one-sentence invariant> | <na welke operatie blijft dit waar?> | <`runtime — inside <fn>` of `compile-time — host-side via @sizeOf check` of `debug-only — caller's test`> |

**Assertion location** is verplicht — vermijd "elsewhere"-formuleringen
(G2 fix). Een rebuilder moet exact weten waar de assert hoort: in de
module zelf, in de caller, of als compile-time check in de host.

## 7. Algorithms

_Per non-triviale functie pseudocode. "Non-triviaal" = bevat conditional_
_branching, modulair rekenen, state-transities, of niet-O(1) loops._
_Triviale assignments overslaan._

**Pseudocode-discipline** _(G7 fix — STRIKT taal-agnostisch)_:
- Toegestaan: `if`, `else`, `while`, `for i in 0..n`, `return`, `mod`,
  `switch`, struct-field-access met `.`, array-index met `[i]`, slice-syntax
  `a[lo..hi]`, arithmetic `+ - * /`, comparison `== != < <= > >=`,
  logical `and or not`.
- **VERBODEN**: taal-specifieke operatoren (`*|`, `+|`, `??`, `?.`,
  `try`, `catch` met language-semantics), built-in type-namen (`usize`,
  `u32`, `i64` — gebruik prose: "saturating multiply at u16 max").
- **VERBODEN**: import-syntax (`@import`, `extern`, `use ::`, `from ... import`).
- Voor saturating/wrapping arithmetic: schrijf de semantiek expliciet uit
  ("multiply, saturating at u16 max = 65535") of gebruik `saturating_mul(...)`.

```
<function_name>(<args>):
    <step>
    if <cond>:
        <action>
    return <value>
```

Onder elk pseudocode-block: eventuele inline noten over invarianten of
edge-gedrag dat uit de code zelf niet evident is.

## 8. Caller contracts

_**Cross-file synthesis**: per public API-functie, in welke source-files_
_en onder welke conditie wordt deze aangeroepen?_

Tabel: `Trigger site | Condition | Args passed | Notes`

| Trigger site | Condition | Args passed | Notes |
|---|---|---|---|
| `<file>:<fn>` | <when does this caller fire?> | <what args are passed> | <invariants the caller assumes> |

**Reden**: state-mutating modules hebben gedrag dat alleen begrepen kan
worden door te weten WANNEER de caller ze gebruikt. Voor blind rebuilder
**essentieel** voor tests (G3 fix — anchors die cross-module beginnen
moeten transformeerbaar zijn naar pure-module calls).

**Post-dispatch contract** _(G9 fix — herhaling van §5 op caller-niveau)_:
welke velden leest de caller AFTER receiving the dispatch action AND
BEFORE de volgende mutating call? Wanneer is state stable, wanneer wordt
het overschreven? Documenteer expliciet om defensive resets in rebuilder
te voorkomen.

## 9. Edge cases

_Genummerde lijst van expliciete edge-cases met expected behavior._
_Doel: anti-bloat — rebuilder hoeft niet defensief te coden voor cases_
_die hier afgehandeld zijn._

- **<edge case name>**: <input/state> → <expected behavior>. <waarom_
  dit gedrag (semantiek-noot)>.
- **empty/null inputs**: ...
- **boundary conditions** (0, max, max+1): ...
- **state-transitions** tussen pre- en post-conditions: ...
- **silent vs error**: welke fouten geven errors, welke worden silent
  geslikt/gesatureerd/gedropt?

## 10. Behaviour anchors

_Test-specs in language-agnostische pseudo-syntax. Doel: rebuilder kan_
_deze 1:1 vertalen naar tests in de doel-taal en groen krijgen._

**Anchor classification** _(verplicht — G5 + G11 fix)_:

| Dimension | Values |
|---|---|
| **Provenance** | `source-extracted` (uit `test "..."` blocks in source — hoge confidence) OR `synthetic` (afgeleid uit spec — medium confidence, dient als invariant-validatie) |
| **Anchor type** | `runtime-behavior` (zoals push/getLine) OR `runtime-state-machine` (state + transitions) OR `compile-time-layout` (`sizeof`, `offsetof`, byte-reinterpret) |
| **Module scope** | `pure-module` (no cross-module input needed) OR `depends_on_module=<X>` (cross-module — needs companion distillate or stub) |

_Gate-check_: data-only modules (geen §5 API) mogen alleen `compile-time-layout`
anchors hebben. State-machines moeten minstens 1 anchor per documented
state-transition hebben (G8 anchor-coverage hint).

### Anchor <ID> — <short description> (`<provenance>`, `<anchor-type>`, `<module-scope>`)

```
Setup: <initial state — exact field values>
Actions: <ordered calls>
Expected after:
  <field> == <value>
  <field> == <value>
```

**Anchor-coverage richtlijn** _(G8 fix, soft gate)_: aim voor minstens
1 anchor per public API function + 1 per documented state-transition +
1 per documented edge case. Voor modules zonder source-tests (`grep -c
'test "' <file>` == 0): alle anchors zullen `synthetic` zijn — dat is
acceptabel mits coverage-richtlijn gehaald is.

## 11. Out-of-scope

_Expliciete lijst van wat deze module **NIET** levert. Doel: anti-bloat —_
_voorkomt dat blind rebuilder defensive code toevoegt voor concerns die_
_bewust buiten scope zijn._

_Minimum 3 items (gate-check). Veelvoorkomend:_

- **Concurrency model**: e.g. "single-writer assumed; no locks/atomics".
- **Persistence**: e.g. "no serialization; lives in process memory only".
- **Dynamic resizing**: e.g. "<CAPACITY> is compile-time constant".
- **Allocator**: e.g. "none required; static storage" of "caller-provided".
- **Search / filtering / iteration**: e.g. "opaque storage, not queryable".
- **Error recovery semantics** buiten gespecificeerde paden.

## 12. Dependency abbreviations

_Inline minimale spec van geïmporteerde types/constants — alleen wat_
_nodig is om de huidige module te begrijpen._

**WAARSCHUWING** _(G13 fix — false-confidence risk)_:
> Abbreviations in §12 zijn **uitsluitend voor contextueel begrip** van
> de huidige module. Ze zijn **GEEN vervanging voor de full distillate**
> van de dependency. Voor stand-alone rebuild van elke dependency:
> consulteer `DISTILLATE/<dep>.md`. Abbreviations missen typisch
> edge-fields, defaults, of compile-time constants die in de huidige
> module niet gebruikt worden — een rebuilder die alleen op abbreviations
> bouwt krijgt **partial coverage met false confidence**.

Per abbreviated dependency:

```
<layout-keyword> struct <TypeName>:    # link: DISTILLATE/<dep>.md voor full spec
    <field>: <type> = <default>
    # ... (alleen velden die deze module raakt)
    # total size = <N> bytes (full layout check in dep's full distillate)
```

Indien geen dependencies: **"n.v.t. — no imports."**

---

## Gate-checks (samenvatting voor scanman-validate)

Een distillaat haalt de v0.6 reproduction-spec gate als:

1. Alle 12 secties aanwezig (of expliciet "n.v.t." waar de specialization
   dat toestaat — zie `repro-spec-data-only.md`).
2. §2 elke dependency-rij heeft Value/Type kolom gevuld (G1).
3. §3 elke constant heeft Value-kolom gevuld (G1).
4. §4 elke type heeft **Memory layout** veld als header-regel (G10).
5. §4 elke field-rij heeft default OF "no default — caller must set".
6. §5 elke functie heeft alle 7 sub-velden (args/effect/returns/pre/post/
   lifetime/post-dispatch-visibility) ingevuld.
7. §6 elke invariant heeft `Assertion location` kolom gevuld (G2).
8. §7 pseudocode bevat geen taal-specifieke operatoren of types (G7).
9. §8 elke caller heeft post-dispatch-contract noot waar van toepassing (G9).
10. §10 elke anchor heeft provenance + anchor-type + module-scope labels (G5/G11).
11. §11 bevat minstens 3 expliciete out-of-scope items.
12. §12 bevat de G13-waarschuwing als er abbreviated dependencies zijn.
