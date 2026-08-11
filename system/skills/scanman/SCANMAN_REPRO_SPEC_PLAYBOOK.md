---
date: 2026-06-01
type: system
tags: [skill, scanman, playbook, reproduction-spec]
id: f2928e45-1756-599b-9554-6df9b534ebb3
---

# Scanman Reproduction-Spec Mode — Agent Execution Playbook

> Operational runbook for any agent (Claude, Pi, Codex, Gemini, etc.) executing
> scanman in reproduction-spec mode. This file + `SKILL.md` together give you
> everything you need to drive the workflow end-to-end without LLM-specific
> knowledge.

## 1. Purpose of this mode

scanman has two operating modes:

| Mode | Output | Use case |
|---|---|---|
| `focused` (v0.5, default) | Architecture distillate — smallest set of concepts | "understand this repo" |
| `reproduction-spec` (v0.6) | Rebuildable spec — rich enough to rebuild in any language without the original source | "distill so AI/dev can rebuild it" |

Trigger on user intent:
- "understand this repo" → `focused`
- "distill so it is rebuildable in language X" → `reproduction-spec`
- "document for AI rebuild" → `reproduction-spec`
- Unclear → `focused` (back-compat)

## 2. Pre-flight checks

- [ ] `zig`, `rustc` or target-language compiler available (for the optional blind-rebuild phase)
- [ ] Target repo local: `~/.opensrc/<provider>/<org>/<repo>/<branch>/` (otherwise run `/opensrc fetch <pkg>` first)
- [ ] `~/agentBrain/scripts/uuid5-gen.sh` executable
- [ ] `~/agentBrain/system/skills/scanman/` present with SKILL.md, VERSION, templates/repro-spec/

Binary detection:
```bash
SCANMAN_BIN=""
if command -v scanman &>/dev/null; then
    SCANMAN_BIN="scanman"
elif [ -x "$HOME/agentBrain/system/skills/scanman/rust-impl/target/release/scanman" ]; then
    SCANMAN_BIN="$HOME/agentBrain/system/skills/scanman/rust-impl/target/release/scanman"
elif [ ! -x "$HOME/agentBrain/system/skills/scanman/scanman-validate.sh" ]; then
    echo "FATAL: no scanman binary AND no bash mirror — install scanman or restore ~/agentBrain/system/skills/scanman/" >&2
    exit 1
fi
# SCANMAN_BIN empty = bash mirror active (scanman-*.sh wrappers).
```

**Calling convention**: the `scanman-*.sh` wrappers are the canonical entry-points
in all phases below. They detect the Rust binary themselves (via
`_scanman-lib.sh::detect_scanman_bin`) and delegate automatically — so the
bash invocations are always correct, with or without the binary. Calling
`$SCANMAN_BIN` directly is an optional shortcut, not a requirement.

## 3. The 6 phases

### Phase 0 — Init workspace

**Slug derivation**: `slug=$(basename <repo-path> | tr '[:upper:]' '[:lower:]')`
OR a user-supplied argument. Expected pattern: short, lowercase, kebab-case —
e.g. `wterm`, `react`, `next-js`. The slug determines the workspace path
`local/research/repo-distill/<slug>/` and the UUID5 seeds of all distillates,
so choose it before init and do not change it afterwards.

```bash
bash ~/agentBrain/system/skills/scanman/scanman-init.sh \
    --mode=reproduction-spec <slug> <repo-path> [goal]
# or via Rust:
$SCANMAN_BIN init --mode=reproduction-spec <slug> <repo-path>
```

Expected output:
- Workspace: `~/agentBrain/local/research/repo-distill/<slug>/`
- Files: `index.md` with a `mode: reproduction-spec` field, `00-file-inventory.md` skeleton
- Subdir: `DISTILLATE/` (empty)
- Subdir: `LEARNINGS.md` (skeleton — see §5 below)

### Phase 1 — Inventory + archetype classification

```bash
bash ~/agentBrain/system/skills/scanman/scanman-scan.sh \
    --mode=reproduction-spec <workspace>
```

Per source file: determine the archetype via heuristics. The **Universal
pattern** column is authoritative (language-independent); the **Detection (Zig
example)** column illustrates how that pattern looks in one concrete language:

| Archetype | Universal pattern | Detection (Zig example) | Template |
|---|---|---|---|
| `data-only` | constants + type definitions, **no methods on the type**, no module state | only `pub const X` + `pub const Y = struct {}` without methods/module state | `data-only.md` |
| `state-machine` | **enum + dispatcher fn** (state-enum, event/action-enum, handler-dispatch) | `State = enum`, `Action = enum`, handler-dispatch | `state-machine.md` |
| `host-export` | **extern/export functions OR module-level mutable state** (FFI/ABI boundary) | `extern fn`, `export fn`, module-level `var X = ...` | `host-export.md` |
| `primitive` | **default fallback** for mixed data+logic modules | — | `primitive.md` |

Output: `00-file-inventory.md` gains an extra `archetype` column.
Manual override: edit `00-file-inventory.md` after inspection.

### Phase 2 — Template instantiation

Per source file in the inventory:
```bash
cp ~/agentBrain/system/skills/scanman/templates/repro-spec/<archetype>.md \
   <workspace>/DISTILLATE/<basename>.md
# Set frontmatter UUID5
NEW_UUID=$(bash ~/agentBrain/scripts/uuid5-gen.sh \
   "local/research/repo-distill/<slug>/DISTILLATE/<basename>")
# Replace the 'id:' line in the new file with $NEW_UUID
```

Or via the Rust binary: `$SCANMAN_BIN scaffold-distillates <workspace>`

Result: `<workspace>/DISTILLATE/<file>.md` per source file, template-ready.

### Phase 3 — Per-file distillation (the LLM work)

For each `<workspace>/DISTILLATE/<file>.md`:

1. Read the source file + dependencies for context (allowed in this phase)
2. Fill in each section according to the per-template instructions
3. Critical disciplines (enforced by the validate gate):
   - §3 constants: explicit **values**, not just names (G1)
   - §4 types: declare `**Memory layout**: regular|extern|packed` (G10)
   - §6 invariants: numbered `I1..In`, with check-trigger (G2)
   - §7 pseudocode: **LANGUAGE-AGNOSTIC** — no Zig `*|`, no Rust `?` (G7)
   - §10 anchors: label `source-extracted` or `synthetic` + pure-module/cross-module (G5, G11)
   - §10 minimum: ≥1 anchor per public function as synthetic (G8)
   - §12 abbreviations: **NOT a substitute** for full dep distillates (G13)

**Cross-file synthesis for §8 (Caller contracts)** — §8 contains information that
is NOT in the module source (who calls, when, with which pre-conditions)
and is empirically the most powerful distillate field. Recipe:

```bash
grep -rn "<module_name>" <repo-path> --include="*.<ext>" | grep -v "<module_file>"
```

Take the **top-3 call-sites** (most frequent or most constraining) and write
**1 bullet per site**: caller function + `file:line`, pre-condition, post-call
expectation, trigger-frequency. In table form:

| Trigger site | Condition | Args | Notes |
|---|---|---|---|
| `Terminal.doLinefeed` | not on alt-screen AND scroll_top == 0 | row + cols | row about to scroll off |

Never skip §8 for "single caller" modules — even a single caller has post-call
discipline (see G9).

### Phase 4 — Validate

```bash
bash ~/agentBrain/system/skills/scanman/scanman-validate.sh \
    --mode=reproduction-spec <workspace>
# or: $SCANMAN_BIN validate --mode=reproduction-spec <workspace>
```

Exit 0 = pass. Exit 1 = fail with **actionable error messages** per file (`file:line` + gate ID + fix-hint).

### Phase 5 — Optional blind-rebuild test (strongest evidence)

Recommended for high-confidence completion:

1. Choose the smallest distillate (typically data-only)
2. Create a test project in the target language (separate dir, no link to source) —
   minimal bootstrap: see Appendix A
3. Rebuild the module from ONLY the distillate (close the source, no grep on the original)
4. Run tests
5. Every "I have to guess / I have to check the source" → `LEARNINGS.md` entry

This is **THE proof that the distillate is rebuildable**. Without phase 5 you do
not know for sure that phase 4 was sufficient — gates check form, blind rebuild checks substance.

### Phase 6 — Complete

Conditions for marking the workspace `status: complete`:
- Phase 4 validate exit 0
- `index.md` `status: complete`
- (Recommended) Phase 5 successful on ≥1 module
- `LEARNINGS.md` updated

## 4. Error recovery — gate failures

Complete gate list G1–G13. Failure messages follow the canonical format
`<file>:<line>: G<x>: <description>. Fix: <hint>`.

| Gate | Failure | Fix | Sample failure message |
|---|---|---|---|
| G1 | Constant without Value column | Add `Value` to the §3 table | `DISTILLATE/cell.md:42: G1: constant 'MAX_COLS' without Value. Fix: add explicit value to the §3 table` |
| G2 | Invariant without check-trigger | Add a `When checked` column | `DISTILLATE/parser.md:88: G2: invariant I3 without check-trigger. Fix: fill the 'When checked' column` |
| G3 | Cross-module anchor missing where §10 expects one | Write the missing anchor, labeled `source-extracted` or `synthetic` | `DISTILLATE/scrollback.md:160: G3: §10 references a cross-module anchor that is missing. Fix: write the anchor with a provenance label` |
| G4 | — | **no fix — out of scope for v0.6**; gate not activated | — |
| G5 | Anchor without provenance label | Add `(source-extracted)` or `(synthetic, pure-module)` | `DISTILLATE/parser.md:201: G5: anchor without provenance label. Fix: add '(source-extracted)' or '(synthetic, pure-module)'` |
| G6 | State-machine without state-reset matrix (§4b) | Add a `## State-reset matrix`: per entry-helper, which state fields it resets/preserves | `DISTILLATE/parser.md:95: G6: state-machine distillate lacks '## State-reset matrix' section. Fix: add a section enumerating each entry-helper and which state fields it touches` |
| G7 | Language-specific pseudocode | Replace with agnostic ops + behavior in prose. Before: `if (buf.pop()) \|item\| return item.?;` → After: `if buffer non-empty: remove and return last element (guaranteed non-null by I2)` | `DISTILLATE/cell.md:77: G7: Zig-specific syntax in §7 pseudocode. Fix: rewrite language-agnostic` |
| G8 | Public function without anchor | Write a synthetic anchor per Public API entry | `DISTILLATE/scrollback.md:180: G8: public function 'push' without anchor. Fix: write a synthetic anchor in §10` |
| G9 | Post-dispatch state visibility missing | Document in §8 which state fields the caller reads after dispatch and until when they remain valid | `DISTILLATE/parser.md:140: G9: state-mutating call without post-dispatch contract. Fix: add 'Caller reads X after dispatch, before next feed()' to §8` |
| G10 | §4 type without Memory layout | Add `**Memory layout**: regular\|extern\|packed` | `DISTILLATE/cell.md:51: G10: type 'Cell' without Memory layout declaration. Fix: add '**Memory layout**: extern'` |
| G11 | Data-only with runtime anchor | Replace with a compile-time layout anchor | `DISTILLATE/cell.md:139: G11: data-only anchor without 'compile-time' kind. Fix: add '(synthetic, pure-module, compile-time)'` |
| G12 | — | **no fix — out of scope as a gate**; constant-groupings are a documentation convention in §3 (see templates), not a blocking check | — |
| G13 | §12 abbreviation as substitute | Reference `DISTILLATE/<dep>.md` instead of an abbreviated spec | `DISTILLATE/terminal.md:230: G13: §12 contains an abbreviated spec of dep 'parser'. Fix: reference DISTILLATE/parser.md` |

**Enforcement coverage**: the bash mirror blocks on G1/G7/G10 (G13 as a warning);
the Rust binary covers G1, G2, G6 (state-machine), G7, G8, G10, G11, G13 (G9 as a
warning). Gates without automation (G3, G5 in bash) are manual-review points
during phase 3 — the validator output flags them explicitly as WARN.

## 4a. Optional: Pi peer-review after Phase 4 (agent-comprehension test)

For extra maturity evidence of the distillate (not only form-correct
but also agent-agnostically understandable):

```bash
bash ~/agentBrain/system/skills/peer-review/bin/peer-review \
    <workspace>/DISTILLATE/<module>.md \
    --to=any --wait=120 \
    --focus="Could a competent LLM agent rebuild this module in <target-language> using ONLY this distillate? Identify ambiguities or missing instructions. Verdict: READY | NEEDS-REVISION | UNCLEAR."
```

Two peer-reviews with different LLMs (e.g. gpt-oss:120b + minimax-m3) yield
**convergence-evidence**: issues that both models find independently are a
strong signal, single-model findings weaker.

**CRITICAL**: after peer-review, **ALWAYS follow the re-evaluation protocol** from
the `~/agentBrain/system/skills/peer-review/SKILL.md` "Post-review re-evaluation"
section. Peer-review is not infallible — false positives occur.
Do not adopt blindly.

## 5. Learning capture protocol — MANDATORY

**This is the feedback loop that matures scanman.** Every v0.6 execution
produces empirical evidence. Do not ignore this.

During phases 3-5: maintain `<workspace>/LEARNINGS.md`:

```markdown
# Learnings — <repo-slug> reproduction-spec execution

## Distillate-writing observations

- File X took N minutes, template archetype <Y> was correct/incorrect
- Section §Z was confusing because... → suggest template improvement
- Caller-contract synthesis (§8) required reading N other files

## Gate-failures encountered

- G<x> at file <f> line <n>: <description> → fix applied: <how>
- Pattern: G<x> repeatedly failed because template instruction was unclear

## Blind-rebuild gaps (phase 5)

- Had to guess: <what> — distillate section <s> missed: <field>
- Had to peek at source: <which file> — distillate section <s> incomplete

## Recommendations for scanman v0.7+

- Template change: ...
- Gate addition: ...
- Process clarification: ...
```

After completion (phase 6): commit to
`~/agentBrain/local/learnings/scanman/scanman-v0-6-execution-<date>-<repo>.md`
with UUID5 frontmatter via `scripts/new-note.sh learning ...`.

**Reason**: v0.6 is a first implementation. Every execution is data for v0.7+.
Without this loop scanman is stuck on its first design.

## 6. Multi-agent parallel dispatch pattern (optional)

For large repos (50+ source files), parallelize phase 3:

```
Orchestrator agent (1):
  - Phase 0-2 (init, inventory, archetype, template scaffold)
  - Dispatch sub-agents for phase 3 (one per source file or per cluster)

Per-file sub-agents (N):
  - Receives: source file path + DISTILLATE template path + caller-grep results
  - Returns: filled distillate file
  - Writes only to its own DISTILLATE file (no cross-write)

Orchestrator (continued):
  - Phase 4 validate (single-process)
  - Route gate-failures back to per-file sub-agents for iteration
  - Optional: Pi peer-review via the /peer-review skill for an agent-agnostic test
```

Works on any agent platform: Claude Code `Agent` tool, Pi worker queue,
Copilot CLI parallel tasks. The gate accepts Markdown files regardless of
which agent wrote them.

## 7. Validation philosophy

A reproduction-spec distillate **IS** the spec. Two criteria for "complete":

1. **Form criterion** (phase 4 gate): mechanically checkable. Exit 0 = form OK.
2. **Substance criterion** (phase 5 blind rebuild): empirical. Tests pass in
   the target language = substance OK.

Form without substance = false confidence. Substance without form = useless
for future agents. Both needed.

This differs from focused mode where "complete enough for purpose" is a subjective
judgment. In reproduction-spec mode, "complete" is objectively verifiable.

### Source-reading discipline

"Rebuildable without source" is about the **distillate**, not about its
**writer**:

- **During distillate writing (phase 3)**: consulting the source is OK — stronger,
  it is required for spec extraction (constants, invariants, caller-grep).
- **The distillate ITSELF** must be rebuildable without source access: all
  information a blind rebuilder needs is contained in it.
- **Phase 5 (blind rebuild)** verifies this by explicitly closing the source:
  no reads, no grep on the original repo during the rebuild.

So there is no contradiction between "may read source in phase 3" and "rebuild
without source in phase 5" — they are two different roles (spec-writer
vs. blind rebuilder) with different access rules.

## Appendix A — Blind-rebuild minimal bootstrap

Goal: a bare test project in which phase 5 can run. This is deliberately the
absolute minimum — full language packs (per-language project skeletons) are
an explicit v0.7+ non-goal (see CHANGELOG 0.6.0).

**Target = Zig** (`mkdir rebuild && cd rebuild`):

```bash
zig init                       # generates build.zig + src/
# src/<module>.zig  ← rebuild target from the distillate
# src/<module>_test.zig:
#   const std = @import("std");
#   const m = @import("<module>.zig");
#   test "anchor A1" { try std.testing.expectEqual(...); }
zig build test
```

**Target = Rust**:

```bash
cargo init --lib
# src/lib.rs ← rebuild target; tests in #[cfg(test)] mod tests
cargo test
```

**Target = Go**:

```bash
go mod init rebuild
# <module>.go ← rebuild target; <module>_test.go with func TestAnchorA1(t *testing.T)
go test ./...
```

Per §10 anchor in the distillate: write one test. Anchors are designed as
directly translatable test cases — no extra test design needed.

## 8. Related

- `SKILL.md` — scanman overall procedure (all modes)
- `templates/repro-spec/{primitive,state-machine,data-only,host-export}.md` — 4 archetype templates
- `CHANGELOG.md` — version history
- `~/agentBrain/local/research/repo-distill/scanman-v0-6-template-empirical-validation-2026-05-31` — design research note
- `~/agentBrain/local/research/repo-distill/scanman-handover-2026-05-31` — predecessor session
- `~/Developer/wterm-rebuild-zig/` — empirical validation project (3 archetypes, 26/26 tests)
</content>
</invoke>
