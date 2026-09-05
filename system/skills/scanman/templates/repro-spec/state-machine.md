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

State-machine specific: explicitly state whether the FSM is **stateful across calls**
(parser-style: state survives between feeds) or **transactional**
(each call starts in a ground state). This determines whether the caller keeps a
persistent instance or creates a fresh one per call.

## 2. Dependencies

_Inherit from base — see `repro-spec-primitive.md` §2._

## 3. Public constants

_Inherit from base — see `repro-spec-primitive.md` §3._

State-machine often: `MAX_PARAMS`, `MAX_INTERMEDIATES`, `MAX_BUFFER`,
timeout-thresholds. Specify values explicitly (G1 fix).

## 4. Public types (state-bag struct)

_Inherit from base — see `repro-spec-primitive.md` §4._

For state-machines, the main struct contains all FSM fields (current state,
accumulators, scratch buffers). The State and Event enums have their own
sections below (§4a, §4b) so they stand out prominently.

## 4a. State enum _(specialization — added)_

Table: `Variant | Meaning | Entry conditions | Exit conditions`.

| Variant | Meaning | Entry conditions | Exit conditions |
|---|---|---|---|
| `<state>` | <one-line semantics> | <which event(s) lead INTO this state?> | <which event(s) lead AWAY from this state?> |

**Ground state** (the "neutral" start state): mark explicitly — that is
where `reset()` / default-init takes you.

**Trap states** (states that can only be left via an explicit reset):
mark explicitly. In the parser e.g. `.csi_ignore` — only left via the
final byte.

## 4b. Event/Action enum + state-reset matrix _(specialization — added)_

### Events / Inputs

Table: `Variant | Trigger | Notes`.

| Variant | Trigger | Notes |
|---|---|---|
| `<event>` | <which input/byte/call triggers this?> | <range / classification> |

### Actions / Outputs

Table: `Variant | Meaning | Caller reads | Lifetime` _(G9 fix —_
_post-dispatch state visibility per action made explicit)_.

| Variant | Meaning | Caller reads | Lifetime |
|---|---|---|---|
| `<action>` | <what should host do?> | <fields the host must read for this action> | <how long are those fields stable?> |

### State-reset matrix _(G6 fix)_

_Mandatory for state-machines with multiple entry-helpers (functions that_
_place the FSM in a state and initialize fields). Makes visible_
_which helper resets vs preserves which fields._

Rows = entry-helpers, columns = state-fields, cells = `reset` / `preserve` / `n/a`.

| Helper / Field | `<field_A>` | `<field_B>` | `<field_C>` | ... |
|---|---|---|---|---|
| `enter<StateX>()` | reset | preserve | n/a | ... |
| `enter<StateY>()` | reset | reset | reset | ... |

**Reason**: subtle bugs arise when helpers are inconsistent (parser
case: `enterEscape` resets 2 fields, `enterCsi` resets 5 — that discrepancy
is only implicitly derivable from the pseudocode without this matrix).

## 5. Public API

_Inherit from base — see `repro-spec-primitive.md` §5._

For state-machines there is typically ONE dominant "step" / "feed" / "tick"
function + a handful of query/reset helpers. Per function, fill in all 7 base fields,
with extra attention to **Post-dispatch state visibility** (G9):
which FSM fields are valid to read after this call, and until when?

## 6. Invariants

_Inherit from base — see `repro-spec-primitive.md` §6._

State-machine specific invariants often: "after Action.X, state ==
ground" and "field Y ∈ [0..MAX_Y]". Link invariants explicitly to
specific action-returns (e.g. "I5: After Action.csi_dispatch: state ==
.ground AND execute_byte holds final byte").

## 7. Algorithms

_Inherit from base — see `repro-spec-primitive.md` §7._

For state-machines: write the master-flow + per-state handlers. Universal
preempts (bytes/events that override EVERY state — parser: ESC, CAN, SUB)
must come **before** the state-switch in the master-flow. Otherwise the
rebuilder misses that the preempt works mid-state.

Pseudocode must be language-agnostic (G7 fix — no `*|`, `try`, etc.).

## 7a. Transition table _(specialization — added)_

_Compact tabular representation of all transitions. Supplementary to §7_
_pseudocode — gives the rebuilder a complete-coverage check._

Table: `From | Event | To | Action emitted | Side-effects`.

| From state | Event / Input | To state | Action emitted | Side-effects |
|---|---|---|---|---|
| `ground` | byte ∈ 0x20..0x7E | `ground` | `print` | set `print_char = byte` |
| `ground` | byte == 0x1B | `escape` | `none` | call `enterEscape()` |
| ... | ... | ... | ... | ... |

**Gate-check** (soft): every (state, event-class) combination from §4a/§4b
must have a row OR be explicitly documented as "unhandled — drops to ground" /
"unreachable". Completeness prevents blind spots.

## 8. Caller contracts

_Inherit from base — see `repro-spec-primitive.md` §8._

Critical for state-machines: the **post-dispatch contract** (which fields
the caller must read between dispatch-return and the next feed call, which are
overwritten). See also the §4b "Caller reads" column — this section gives the
broader context (when does the caller dispatch, in which loop structure).

## 9. Edge cases

_Inherit from base — see `repro-spec-primitive.md` §9._

State-machine specific edge cases:
- **Mid-state preempts**: what happens if the universal preempt arrives
  mid-X? Which fields remain, which are reset?
- **Saturation / clamping**: numeric params that overflow — saturating
  or wrapping?
- **Invalid transitions**: input that has no valid transition — drop,
  ignore, error?

## 10. Behaviour anchors

_Inherit from base — see `repro-spec-primitive.md` §10._

For state-machines: anchor type is typically `runtime-state-machine`
(combination of setup-state, sequence-of-inputs, and assertions over
both the returned action and post-state fields).

**Anchor-coverage guideline** _(G8 fix, soft gate for state-machines)_:
- At least 1 anchor per state-transition from §7a.
- At least 1 anchor per universal preempt × major state combination.
- At least 1 anchor per documented saturation/clamp edge case.

For the parser archetype, 13 anchors were sufficient for 8 states + 6 actions.
Scale proportionally: more states ≠ quadratically more anchors, provided the
master-flow is uniform enough.

## 11. Out-of-scope

_Inherit from base — see `repro-spec-primitive.md` §11._

State-machine common out-of-scope: timeouts, retries, persistent
state across reset, parallel processing of multiple streams.

## 12. Dependency abbreviations

_Inherit from base — see `repro-spec-primitive.md` §12._

State-machines often have few/no dependencies (parser: zero deps).
If absent: write "not applicable" and keep the §12 header for structural
consistency with other distillates.

---

## Gate-checks (delta from base)

In addition to the 12 base gate-checks, for the state-machine specialization:

13. §4a present with at least 2 state variants and entry/exit per variant.
14. §4b present with events AND actions, both with a table.
15. §4b state-reset matrix present if the module has ≥2 entry-helpers (G6).
16. §7a transition table present, with coverage for all (state, major-event-class)
    pairs OR explicit "unhandled" annotations.
</content>
