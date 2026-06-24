# Repro-Spec — <Module name> (host-export specialization)

> **Template**: `repro-spec-host-export` (specialization of `repro-spec-primitive`)
> **Inherits**: §1, §2, §3, §4, §6, §7, §9, §10, §11, §12.
> **Overrides**: §5 (Public API) — replaced by §5a (Export ABI) + §5b
>          (Host-managed state).
> **Extends**: §8 (Caller contracts) — covers the cross-language boundary
>          explicitly, not just the in-language caller.
>
> Use this specialization when the module is a **host-export surface**:
> WASM `export "C"` API, FFI shim, JNI bridge, COM/IDL surface, DLL/SO
> public symbols, IPC RPC schema. The defining property: callers live in
> a **different language runtime** and may interact through a constrained
> ABI (no language-level types, only raw memory + primitives).
>
> Empirical reference target: `wasm_api.zig` in WTerm (Zig → JS/WASM
> boundary). This specialization is structurally validated but not yet
> blind-rebuild-validated; treat as v0.6-draft pending validation #4.

---

## 1. Identity

_Inherit from base — see `repro-spec-primitive.md` §1._

Host-export specifiek: noem **host runtime** (JS/V8, JVM, .NET CLR,
native C ABI, etc.) en **transport mechanism** (WASM linear memory + JS
ArrayBuffer view, JNI handles, COM vtables, IPC named pipe).

`Caller(s)` lijst is hier **cross-language**: e.g. "TypeScript renderer
via `wterm.wasm` import; reads return values + reads/writes shared linear
memory regions".

## 2. Dependencies

_Inherit from base — see `repro-spec-primitive.md` §2._

Host-export modules importeren typisch de **gehele in-language module
graaf** (alle primitives die ze willen exposen). Vermeld minstens de
top-level modules — niet elke transitive import, maar elke module die
direct als type of methode in de export-surface verschijnt.

## 3. Public constants

_Inherit from base — see `repro-spec-primitive.md` §3._

Host-exports vaak: layout constants (`CELL_BYTE_SIZE`, `MAX_GRID_BYTES`),
opcode IDs, status-code enums die als raw integers over de ABI gaan.
**Verplicht** waarden noemen (G1) — de host-side parser leest letterlijke
integers, geen language-symbols.

## 4. Public types

_Inherit from base — see `repro-spec-primitive.md` §4._

Voor host-exports: ALLE types die over de boundary gaan moeten
`extern struct` / `repr(C)` / `packed` zijn (G10 — verplicht). De
**Memory layout** veld is hier hard-fail bij ontbreken — geen layout
contract = geen cross-language access.

## 5a. Export ABI _(specialization — replaces §5)_

_Per exported symbol één sub-sectie. ABI-discipline: signatures uitschrijven_
_in language-neutraal IDL (geen Zig `[*]const u8`, geen Rust `&[u8]` —_
_gebruik `const u8*` of `(ptr: u32, len: u32)` pair). Calling convention_
_expliciet (cdecl / stdcall / wasm32, etc.)._

### `<exported_symbol>`

- **Linkage**: `extern "C"` / `#[no_mangle]` / `WASM export` / `JNI` / `COM`
- **Calling convention**: `cdecl` / `stdcall` / `wasm32` / etc.
- **C-equivalent signature**:
  ```c
  return_type symbol_name(arg_type arg_name, ...);
  ```
- **Memory ownership** _(kritiek voor host-export)_:
  - Wie alloceert input buffers? (host pre-alloceert / module callback-alloceert)
  - Wie alloceert return buffers / strings?
  - Wie free't, wanneer?
  - Mag de host de pointer bewaren tussen calls?
- **Marshalling rules**:
  - Strings: UTF-8 raw bytes + length pair? Null-terminated? UTF-16?
  - Structs: by-value (copy) of by-pointer (shared)?
  - Arrays: pointer + length pair? Sentinel-terminated?
- **Errors over the boundary**:
  - Return-code conventie? (0 = success, non-zero = errno-like?)
  - Out-of-band signaling? (last-error register, exception unwinding,
    return-value-is-error-union)?
- **Effect** (genummerde stappen — wat gebeurt host-side en module-side?)
- **Returns** (incl. wat de host moet doen met return value)
- **Pre-conditions** (wat de host moet garanderen — vaak: "memory at
  `ptr[0..len]` must be readable", "instance must be initialized via
  `<init_fn>`")
- **Post-conditions** (wat altijd waar is na de call — vaak: "linear
  memory region `[OUT_PTR..OUT_PTR+N]` populated with...")

## 5b. Host-managed state _(specialization — added)_

_Module-level state die buiten een call-context leeft (singletons,_
_globale arenas, init-once handles). Voor host-exports kritiek omdat_
_de host-runtime niet weet wat de module-side bewaart tussen calls._

| Symbol | Type | Lifetime | Initialized by | Notes |
|---|---|---|---|---|
| `<global_var>` | `<type>` | `static` / `lazy-init` / `per-instance` | `<init_fn>` / module load / first call | <thread-safety, re-init semantics> |

**Init order requirements** (verplicht indien niet trivial): in welke
volgorde MOET de host de init-functies aanroepen? Bv. "host MUST call
`init_terminal(rows, cols)` before any `feed_byte(...)` call; otherwise
behavior is undefined".

**Reset semantics**: kan de host de module-state resetten zonder
re-loading? Welke API? Welke fields blijven, welke gaan weg? (Parallel
aan G6 state-reset matrix uit `repro-spec-state-machine`, maar voor
host-managed globals.)

## 6. Invariants

_Inherit from base — see `repro-spec-primitive.md` §6._

Host-export specifiek: invariants op linear-memory regions ("region
`[CELLS_PTR..CELLS_PTR + rows*cols*12]` is altijd readable na init")
en op cross-call state ("`getTerminalRows()` returns dezelfde waarde
tot expliciete `resize()` call").

## 7. Algorithms

_Inherit from base — see `repro-spec-primitive.md` §7._

Voor host-exports: pseudocode moet **dubbel taal-agnostisch** zijn —
zowel onafhankelijk van module-language (G7) als van host-language. Beschrijf
data-flow in termen van linear-memory offsets / ABI-types, niet
in-language slice-types.

## 8. Caller contracts _(extended for cross-language boundary)_

_Inherit base §8 + voeg cross-language sub-tabel toe._

### In-language callers

(zoals base — meestal n.v.t. voor pure export modules, of "host glue
code only").

### Cross-language callers

| Host-side caller | Language | Call pattern | Marshalling | Notes |
|---|---|---|---|---|
| `<host file/module>` | TS / JS / Rust / C / Python | `<sync call>` / `<async via event>` / `<polling loop>` | <how do values cross — copies, shared memory, handles?> | <ordering guarantees, batching, threading model> |

**Boundary contract** (verplicht):
- **Threading model**: is de module single-threaded? Moet host serializen?
- **Re-entrancy**: mag een export-call een andere export-call triggeren
  (callback into host, host calls back into module)? Welke functies
  zijn re-entrant-safe?
- **Memory views**: welke linear-memory regions mag host lezen? Schrijven?
  Welke zijn stable across calls, welke worden invalided door welke
  mutating call? (G9 cross-language equivalent.)
- **Exception/panic semantics**: wat als de module crasht? Trap? Return
  error code? Leak resources?

## 9. Edge cases

_Inherit from base — see `repro-spec-primitive.md` §9._

Host-export specifieke edge cases:
- **Calling exports before init**: trap, return error, undefined behavior?
- **Concurrent calls from multiple host threads**: serialized, raced,
  detected-and-rejected?
- **Pointer/length pair with len=0**: valid no-op, error, undefined?
- **Pointer/length pair with len > buffer-size**: bounds-check, trust-caller,
  trap?
- **Host releases shared-memory view mid-call**: usually n/a for WASM
  (linear memory persists), critical for FFI with caller-owned buffers.

## 10. Behaviour anchors

_Inherit from base — see `repro-spec-primitive.md` §10._

Voor host-export anchors zijn typisch:
- **Runtime-behavior** anchors (call exported fn, observe linear-memory
  state) — `pure-module` mits geen depend op interne module state via
  in-language calls.
- **Compile-time-layout** anchors over exported types (cross-language
  ABI-stabiliteit — paragraaf van G11).

Anchors moeten geschreven worden in host-call-syntax (pseudo-syntax voor
"host calls `symbol(args)`, then reads memory at `ptr[0..N]`") zodat ze
in willekeurige host-taal reproducibel zijn.

## 11. Out-of-scope

_Inherit from base — see `repro-spec-primitive.md` §11._

Host-export veelvoorkomend out-of-scope:
- **Async/promise semantics** in host-language (out — module exposes
  synchronous primitives only).
- **GC integration** (module-side memory is not GC-managed; host wraps).
- **Type-safety on the host side** (module exposes raw ABI; host is
  responsible for typed wrappers).
- **Versioning/compat across module updates** (vaak out — geen ABI
  version-negotiation built-in).

## 12. Dependency abbreviations

_Inherit from base — see `repro-spec-primitive.md` §12._

Host-export modules importeren vaak meerdere primitives — de G13-warning
is hier extra relevant. Liever per dependency een one-liner met link naar
full distillate dan een uitvoerige inline-spec.

---

## Gate-checks (delta van base)

Naast de 12 base gate-checks, voor host-export specialization:

13. §5a per exported symbol: linkage, calling convention, C-equivalent
    signature, memory ownership, marshalling rules — alle aanwezig.
14. §5b host-managed state-tabel aanwezig (of expliciet "n.v.t. — module
    holds no cross-call state").
15. §5b init-order requirements gedocumenteerd indien meerdere init-fns
    bestaan.
16. §8 cross-language callers sub-tabel aanwezig + Boundary contract
    paragraaf (threading + re-entrancy + memory views + panic).
17. §4 alle types die in §5a verschijnen MOETEN `extern`/`repr(C)`/`packed`
    layout hebben (G10 hard-fail).
