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

Host-export specific: name the **host runtime** (JS/V8, JVM, .NET CLR,
native C ABI, etc.) and the **transport mechanism** (WASM linear memory + JS
ArrayBuffer view, JNI handles, COM vtables, IPC named pipe).

The `Caller(s)` list here is **cross-language**: e.g. "TypeScript renderer
via `wterm.wasm` import; reads return values + reads/writes shared linear
memory regions".

## 2. Dependencies

_Inherit from base — see `repro-spec-primitive.md` §2._

Host-export modules typically import the **entire in-language module
graph** (all primitives they want to expose). Mention at least the
top-level modules — not every transitive import, but every module that
appears directly as a type or method in the export surface.

## 3. Public constants

_Inherit from base — see `repro-spec-primitive.md` §3._

Host-exports often: layout constants (`CELL_BYTE_SIZE`, `MAX_GRID_BYTES`),
opcode IDs, status-code enums that go over the ABI as raw integers.
**Mandatory** to name values (G1) — the host-side parser reads literal
integers, not language symbols.

## 4. Public types

_Inherit from base — see `repro-spec-primitive.md` §4._

For host-exports: ALL types that cross the boundary must be
`extern struct` / `repr(C)` / `packed` (G10 — mandatory). The
**Memory layout** field is a hard-fail here when missing — no layout
contract = no cross-language access.

## 5a. Export ABI _(specialization — replaces §5)_

_One sub-section per exported symbol. ABI discipline: write out signatures_
_in language-neutral IDL (no Zig `[*]const u8`, no Rust `&[u8]` —_
_use `const u8*` or a `(ptr: u32, len: u32)` pair). Calling convention_
_explicit (cdecl / stdcall / wasm32, etc.)._

### `<exported_symbol>`

- **Linkage**: `extern "C"` / `#[no_mangle]` / `WASM export` / `JNI` / `COM`
- **Calling convention**: `cdecl` / `stdcall` / `wasm32` / etc.
- **C-equivalent signature**:
  ```c
  return_type symbol_name(arg_type arg_name, ...);
  ```
- **Memory ownership** _(critical for host-export)_:
  - Who allocates input buffers? (host pre-allocates / module callback-allocates)
  - Who allocates return buffers / strings?
  - Who frees, and when?
  - May the host keep the pointer between calls?
- **Marshalling rules**:
  - Strings: UTF-8 raw bytes + length pair? Null-terminated? UTF-16?
  - Structs: by-value (copy) or by-pointer (shared)?
  - Arrays: pointer + length pair? Sentinel-terminated?
- **Errors over the boundary**:
  - Return-code convention? (0 = success, non-zero = errno-like?)
  - Out-of-band signaling? (last-error register, exception unwinding,
    return-value-is-error-union)?
- **Effect** (numbered steps — what happens host-side and module-side?)
- **Returns** (incl. what the host must do with the return value)
- **Pre-conditions** (what the host must guarantee — often: "memory at
  `ptr[0..len]` must be readable", "instance must be initialized via
  `<init_fn>`")
- **Post-conditions** (what is always true after the call — often: "linear
  memory region `[OUT_PTR..OUT_PTR+N]` populated with...")

## 5b. Host-managed state _(specialization — added)_

_Module-level state that lives outside a call context (singletons,_
_global arenas, init-once handles). Critical for host-exports because_
_the host runtime does not know what the module side keeps between calls._

| Symbol | Type | Lifetime | Initialized by | Notes |
|---|---|---|---|---|
| `<global_var>` | `<type>` | `static` / `lazy-init` / `per-instance` | `<init_fn>` / module load / first call | <thread-safety, re-init semantics> |

**Init order requirements** (mandatory if not trivial): in which
order MUST the host call the init functions? E.g. "host MUST call
`init_terminal(rows, cols)` before any `feed_byte(...)` call; otherwise
behavior is undefined".

**Reset semantics**: can the host reset the module state without
re-loading? Which API? Which fields remain, which go away? (Parallel
to the G6 state-reset matrix from `repro-spec-state-machine`, but for
host-managed globals.)

## 6. Invariants

_Inherit from base — see `repro-spec-primitive.md` §6._

Host-export specific: invariants on linear-memory regions ("region
`[CELLS_PTR..CELLS_PTR + rows*cols*12]` is always readable after init")
and on cross-call state ("`getTerminalRows()` returns the same value
until an explicit `resize()` call").

## 7. Algorithms

_Inherit from base — see `repro-spec-primitive.md` §7._

For host-exports: pseudocode must be **doubly language-agnostic** —
independent of both the module language (G7) and the host language. Describe
data flow in terms of linear-memory offsets / ABI types, not
in-language slice types.

## 8. Caller contracts _(extended for cross-language boundary)_

_Inherit base §8 + add a cross-language sub-table._

### In-language callers

(as in base — usually not applicable for pure export modules, or "host glue
code only").

### Cross-language callers

| Host-side caller | Language | Call pattern | Marshalling | Notes |
|---|---|---|---|---|
| `<host file/module>` | TS / JS / Rust / C / Python | `<sync call>` / `<async via event>` / `<polling loop>` | <how do values cross — copies, shared memory, handles?> | <ordering guarantees, batching, threading model> |

**Boundary contract** (mandatory):
- **Threading model**: is the module single-threaded? Must the host serialize?
- **Re-entrancy**: may an export call trigger another export call
  (callback into host, host calls back into module)? Which functions
  are re-entrant-safe?
- **Memory views**: which linear-memory regions may the host read? Write?
  Which are stable across calls, which are invalidated by which
  mutating call? (G9 cross-language equivalent.)
- **Exception/panic semantics**: what if the module crashes? Trap? Return
  error code? Leak resources?

## 9. Edge cases

_Inherit from base — see `repro-spec-primitive.md` §9._

Host-export specific edge cases:
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

For host-export, anchors are typically:
- **Runtime-behavior** anchors (call exported fn, observe linear-memory
  state) — `pure-module` provided there is no dependence on internal module state via
  in-language calls.
- **Compile-time-layout** anchors over exported types (cross-language
  ABI stability — paragraph of G11).

Anchors must be written in host-call syntax (pseudo-syntax for
"host calls `symbol(args)`, then reads memory at `ptr[0..N]`") so that they
are reproducible in any host language.

## 11. Out-of-scope

_Inherit from base — see `repro-spec-primitive.md` §11._

Host-export common out-of-scope:
- **Async/promise semantics** in the host language (out — module exposes
  synchronous primitives only).
- **GC integration** (module-side memory is not GC-managed; host wraps).
- **Type-safety on the host side** (module exposes raw ABI; host is
  responsible for typed wrappers).
- **Versioning/compat across module updates** (often out — no ABI
  version-negotiation built-in).

## 12. Dependency abbreviations

_Inherit from base — see `repro-spec-primitive.md` §12._

Host-export modules often import multiple primitives — the G13 warning
is extra relevant here. Prefer a one-liner per dependency with a link to the
full distillate over an elaborate inline spec.

---

## Gate-checks (delta from base)

In addition to the 12 base gate-checks, for the host-export specialization:

13. §5a per exported symbol: linkage, calling convention, C-equivalent
    signature, memory ownership, marshalling rules — all present.
14. §5b host-managed state table present (or explicit "not applicable — module
    holds no cross-call state").
15. §5b init-order requirements documented if multiple init-fns
    exist.
16. §8 cross-language callers sub-table present + Boundary contract
    paragraph (threading + re-entrancy + memory views + panic).
17. §4 all types that appear in §5a MUST have `extern`/`repr(C)`/`packed`
    layout (G10 hard-fail).
</content>
