# Repro-Spec — <Module name> (state-machine specialization)

> **Template**: `repro-spec-state-machine` (specialization of `repro-spec-primitive`)
> **Inherits**: all 12 base sections from `repro-spec-primitive.md`.
> **Adds**: §4a (State enum), §4b (Event/Action enum + state-reset matrix),
>          §7a (Transition table).
> **Overrides**: §4 (Public types) — the main state-bag struct sits below
>          §4a/§4b so readers encounter the enums first.
>
> Use this specialization when the module is a finite-state machine:
> protocol parser, lexer, controller, lifecycle manager, retry/circuit
> breaker. Empirical validation: `parser.zig` (VT100/CSI/OSC parser,
> 8 states, 13 anchors).

---

## 1. Identity

_Inherit from base — see `repro-spec-primitive.md` §1._

State-machine specific: noem expliciet of de FSM **stateful across calls**
is (parser-style: state survives between feeds) of **transactional**
(elke call begint in een ground state). Dit bepaalt of de caller een
persistent instance houdt of per-call een verse aanmaakt.

## 2. Dependencies

_Inherit from base — see `repro-spec-primitive.md` §2._

## 3. Public constants

_Inherit from base — see `repro-spec-primitive.md` §3._

State-machine vaak: `MAX_PARAMS`, `MAX_INTERMEDIATES`, `MAX_BUFFER`,
timeout-thresholds. Vermeld waarden expliciet (G1 fix).

## 4. Public types (state-bag struct)

_Inherit from base — see `repro-spec-primitive.md` §4._

Voor state-machines bevat de hoofdstruct alle FSM-velden (current state,
accumulators, scratch-buffers). De State- en Event-enums hebben hun eigen
secties hieronder (§4a, §4b) zodat ze prominent staan.

## 4a. State enum _(specialization — added)_

Tabel: `Variant | Meaning | Entry conditions | Exit conditions`.

| Variant | Meaning | Entry conditions | Exit conditions |
|---|---|---|---|
| `<state>` | <one-line semantics> | <welke event(s) leiden HIER naar toe?> | <welke event(s) leiden NAAR HIER weer weg?> |

**Ground state** (de "neutrale" startstaat): markeer expliciet — dat is
waar `reset()` / default-init naartoe brengt.

**Trap states** (states waaruit alleen via expliciete reset weggekomen
wordt): markeer expliciet. Bij parser bv. `.csi_ignore` — alleen verlaten
via final byte.

## 4b. Event/Action enum + state-reset matrix _(specialization — added)_

### Events / Inputs

Tabel: `Variant | Trigger | Notes`.

| Variant | Trigger | Notes |
|---|---|---|
| `<event>` | <welke input/byte/call triggert dit?> | <range / classificatie> |

### Actions / Outputs

Tabel: `Variant | Meaning | Caller reads | Lifetime` _(G9 fix —_
_post-dispatch state visibility per action expliciet)_.

| Variant | Meaning | Caller reads | Lifetime |
|---|---|---|---|
| `<action>` | <what should host do?> | <fields the host must read for this action> | <how long are those fields stable?> |

### State-reset matrix _(G6 fix)_

_Verplicht voor state-machines met meerdere entry-helpers (functies die_
_de FSM in een state plaatsen en velden initialiseren). Maakt zichtbaar_
_welke helper welke velden reset vs preserve._

Rijen = entry-helpers, kolommen = state-fields, cellen = `reset` / `preserve` / `n/a`.

| Helper / Field | `<field_A>` | `<field_B>` | `<field_C>` | ... |
|---|---|---|---|---|
| `enter<StateX>()` | reset | preserve | n/a | ... |
| `enter<StateY>()` | reset | reset | reset | ... |

**Reden**: subtle bugs ontstaan als helpers inconsistent zijn (parser
case: `enterEscape` reset 2 velden, `enterCsi` reset 5 — die discrepantie
is alleen impliciet uit pseudocode af te leiden zonder deze matrix).

## 5. Public API

_Inherit from base — see `repro-spec-primitive.md` §5._

Voor state-machines is typisch ÉÉN dominante "step" / "feed" / "tick"
functie + een handful query/reset helpers. Per functie alle 7 base-velden
invullen, met extra aandacht voor **Post-dispatch state visibility** (G9):
welke FSM-velden zijn na deze call geldig om te lezen, en tot wanneer?

## 6. Invariants

_Inherit from base — see `repro-spec-primitive.md` §6._

State-machine specifieke invariants vaak: "after Action.X, state ==
ground" en "field Y ∈ [0..MAX_Y]". Verbind invariants expliciet aan
specifieke action-returns (bv. "I5: After Action.csi_dispatch: state ==
.ground AND execute_byte holds final byte").

## 7. Algorithms

_Inherit from base — see `repro-spec-primitive.md` §7._

Voor state-machines: schrijf master-flow + per-state handlers. Universal
preempts (bytes/events die ELKE state overrulen — parser: ESC, CAN, SUB)
moeten **vóór** de state-switch staan in de master-flow. Anders mist
rebuilder dat de preempt mid-state werkt.

Pseudocode moet taal-agnostisch zijn (G7 fix — geen `*|`, `try`, etc.).

## 7a. Transition table _(specialization — added)_

_Compacte tabular weergave van alle transitions. Aanvullend op §7_
_pseudocode — geeft rebuilder een complete-coverage check._

Tabel: `From | Event | To | Action emitted | Side-effects`.

| From state | Event / Input | To state | Action emitted | Side-effects |
|---|---|---|---|---|
| `ground` | byte ∈ 0x20..0x7E | `ground` | `print` | set `print_char = byte` |
| `ground` | byte == 0x1B | `escape` | `none` | call `enterEscape()` |
| ... | ... | ... | ... | ... |

**Gate-check** (soft): elke (state, event-class) combinatie uit §4a/§4b
moet een rij hebben OF expliciet als "unhandled — drops to ground" /
"unreachable" gedocumenteerd zijn. Compleetheid voorkomt blinde spots.

## 8. Caller contracts

_Inherit from base — see `repro-spec-primitive.md` §8._

Voor state-machines kritiek: de **post-dispatch contract** (welke velden
moet caller lezen tussen dispatch-return en next feed-call, welke worden
overschreven). Zie ook §4b "Caller reads" kolom — deze sectie geeft de
bredere context (wanneer dispatcht de caller, in welke loop-structuur).

## 9. Edge cases

_Inherit from base — see `repro-spec-primitive.md` §9._

State-machine specifieke edge cases:
- **Mid-state preempts**: wat gebeurt er als de universal preempt mid-X
  binnenkomt? Welke velden blijven, welke worden gereset?
- **Saturation / clamping**: numerieke params die overflowen — saturating
  of wrapping?
- **Invalid transitions**: input die geen geldige transition heeft — drop,
  ignore, fout?

## 10. Behaviour anchors

_Inherit from base — see `repro-spec-primitive.md` §10._

Voor state-machines: anchor-type is typisch `runtime-state-machine`
(combinatie van setup-state, sequence-of-inputs, en assertions over
zowel returned action als post-state fields).

**Anchor-coverage richtlijn** _(G8 fix, soft gate voor state-machines)_:
- Minstens 1 anchor per state-transition uit §7a.
- Minstens 1 anchor per universal preempt × major state combinatie.
- Minstens 1 anchor per documented saturation/clamp edge case.

Voor parser-archetype was 13 anchors voldoende voor 8 states + 6 actions.
Schaal proportioneel: meer states ≠ kwadratisch meer anchors, mits de
master-flow uniform genoeg is.

## 11. Out-of-scope

_Inherit from base — see `repro-spec-primitive.md` §11._

State-machine veelvoorkomend out-of-scope: timeouts, retries, persistent
state across reset, parallel-processing of meerdere streams.

## 12. Dependency abbreviations

_Inherit from base — see `repro-spec-primitive.md` §12._

State-machines hebben vaak weinig/geen dependencies (parser: zero deps).
Indien afwezig: schrijf "n.v.t." en behoud de §12-header voor structurele
consistentie met andere distillaten.

---

## Gate-checks (delta van base)

Naast de 12 base gate-checks, voor state-machine specialization:

13. §4a aanwezig met minstens 2 state-variants en entry/exit per variant.
14. §4b aanwezig met events EN actions, beide met tabel.
15. §4b state-reset matrix aanwezig indien de module ≥2 entry-helpers heeft (G6).
16. §7a transition-table aanwezig, met dekking voor alle (state, major-event-class)
    paren OF expliciete "unhandled" annotaties.
