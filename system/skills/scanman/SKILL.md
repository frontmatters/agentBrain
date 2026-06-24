---
name: scanman
description: Analyze a repository end-to-end, reconstruct its architecture, map dependencies and runtime flows, extract its core primitives, and redesign the useful parts into a simpler reusable target model.
argument-hint: Repo name/path and analysis goal
user-invocable: true
resources:
  - system/rules.md
  - local/learnings/patterns.md
  - templates/repo-distill-index.md
  - templates/repo-distill-file-inventory.md
  - templates/repo-distill-dependency-map.md
  - templates/repo-distill-system-map.md
  - templates/repo-distill-runtime-model.md
  - templates/repo-distill-core-primitives.md
  - templates/repo-distill-risk-and-bloat.md
  - templates/repo-distill-redesign-v1.md
  - scripts/scanman-init.sh
  - scripts/scanman-scan.sh
  - scripts/scanman-validate.sh
---

# Scanman

Use this when a repo should be **understood, mapped, scanned, distilled, and improved** rather than merely patched.

Default expectation: if the user gives only a repo/path, Scanman should autonomously iterate until it can produce the strongest complete output it can justify, not stop at the first bootstrap pass unless blocked.

## Operating Modes
- `bootstrap` — generate the initial inventory/maps and make uncertainty explicit
- `strict-runtime` — prove entrypoints, verified call paths, callback/event loops, and verified-only main pseudocode
- `strict-distill` — complete `03`, `04`, and `05` with evidence-based primitives, risk/bloat, and redesign
- `complete` — the default target for serious scans; iterate through bootstrap + strict-runtime + strict-distill before calling the scan meaningfully complete

If the user does not specify a mode, prefer `complete` for serious repo analysis.

## Completion Rule
Do not present Scanman as complete just because `00/00b/01/02` exist.
A serious scan is only "complete enough" when:
- runtime proof is strong enough for current conclusions
- `03-core-primitives.md` is materially filled
- `04-risk-and-bloat.md` is materially filled
- `05-redesign-v1.md` is materially filled
- remaining unknowns are explicit and bounded

If multiple iterations are needed, that iteration burden belongs to Scanman, not the user.

## Validation Gate (mandatory)

Scanman's completion claim is **not** a judgment call. It is gated by `scripts/scanman-validate.sh`, which any agent on any platform can execute.

### The loop the agent MUST follow

```text
1. bootstrap     → bash scripts/scanman-scan.sh <repo-path> <slug>
2. enrich        → agent fills 01/02/03/04/05 with verified-first content
3. validate      → bash scripts/scanman-validate.sh <workspace-dir>
   ├── exit 0  → agent MAY claim "complete enough" and stop
   └── exit 1  → agent MUST read the failure reasons and iterate on
                 the named files until validate exits 0
4. (exit 2 only on usage / missing path — fix invocation, then re-run)
```

### Rules

- **Never claim "complete enough" without a passing validate run.** The exit code is the only authoritative completion signal.
- **Never weaken validate thresholds to make a scan pass.** Thresholds are tuned to reject thin stubs; if a file legitimately cannot meet them, the scan is not yet complete.
- **Iterate, do not give up at the first failure.** Each failure line names the file and the reason. Address them in order.
- **Validate is agent-agnostic.** Pure bash, exit codes, stderr-formatted reasons. Works for any agent that can execute a shell command and read its output.

### Environment overrides (only when justified)

`scanman-validate.sh` reads:

- `SCANMAN_MIN_WORDS`    (default 300) — minimum word count for 03/04/05
- `SCANMAN_MIN_ITEMS`    (default 3)   — minimum substantial bullets per file
- `SCANMAN_MIN_BULLET_LEN` (default 30) — minimum chars for a bullet to count as substantial
- `SCANMAN_MIN_CLAIM_LABELS` (default 3) — minimum `verified`/`inferred`/`unknown` markers in 02/03/04/05
- `SCANMAN_MIN_SECTION_WORDS` (default 25) — minimum words per `## ` section body in 03/04/05
- `SCANMAN_MAX_THIN_SECTIONS` (default 2) — max sections per file below `SCANMAN_MIN_SECTION_WORDS` before failing
- `SCANMAN_EXEMPT_SECTIONS` (default `^(Related|Purpose|Decision)$`) — regex of section names that are legitimately short and skipped by the thin-section check
- `SCANMAN_REQUIRE_EVIDENCE` (default `0`, opt-in) — when `1`, every `02/03/04` file with `verified` claims must contain at least one source-path reference (e.g. `packages/foo/bar.ts`, `src/baz.zig`). Closes the gap where `verified` could be claimed correct-by-luck without an actual source read. `05` is exempted because redesign refers to primitives from `03` by name, not to source files. A stricter `file:line` mode is planned for v0.0.6.

Defaults exist for a reason. Override only when documenting why in the scan's `index.md`.

### Why the section-density check exists

Without it, an agent can pass the gate by filling only the first table in a file and leaving every other section as untouched template boilerplate (e.g. `## Essential Concepts` with `- definition / - why it exists / - what breaks without it`). The section-density check fails those workspaces with explicit per-section feedback the agent can act on.

## User Contract
- Minimal input should be enough: repo/path plus optional goal
- Scanman should do the iterative enrichment work itself
- The user should receive one canonical workspace with explicit status, not a pile of half-finished sibling passes unless comparison is intentional
- If Scanman stops early, it must say whether it is blocked, still in progress, or complete enough for the requested purpose

## Outputs

Use this canonical folder layout:

```text
local/research/repo-distill/<repo-slug>/
├── index.md
├── 00-file-inventory.md
├── 00b-dependency-map.md
├── 01-system-map.md
├── 02-runtime-model.md
├── 03-core-primitives.md
├── 04-risk-and-bloat.md
└── 05-redesign-v1.md
```

Use these templates:
- `templates/repo-distill-index.md`
- `templates/repo-distill-file-inventory.md`
- `templates/repo-distill-dependency-map.md`
- `templates/repo-distill-system-map.md`
- `templates/repo-distill-runtime-model.md`
- `templates/repo-distill-core-primitives.md`
- `templates/repo-distill-risk-and-bloat.md`
- `templates/repo-distill-redesign-v1.md`

Optional helpers:
- `bash scripts/scanman-init.sh <repo-slug> [repo-path] [goal...]`
- `bash scripts/scanman-scan.sh <repo-path> [repo-slug]`

Mandatory gate (see "Validation Gate" above):
- `bash scripts/scanman-validate.sh <workspace-dir>`

`scanman-scan.sh` is a bootstrap/enrichment helper, not the final authority. Its job is to seed or enrich the canonical docs, not to create throwaway parallel pass docs.
`scanman-validate.sh` IS the final authority on completion. Its exit code determines whether a scan may be declared "complete enough".

Method/version reference:
- `system/skills/scanman/VERSION.md`

Store project-specific analysis under `local/research/repo-distill/<repo-slug>/` by default.
Only put it under `local/projects/[name]/` when the repo analysis is directly part of an ongoing project record.
Store reusable HOW/WHERE patterns separately only after they are proven reusable.

## Procedure

### 0. Detect the stack
- Detect the primary language(s), framework(s), packaging/build tools, and likely runtime style before deeper tracing
- Use that detection to prioritize likely entrypoints and hotspots
- When available, consult a language/framework-aware context source (for example Context7) only as an assistive lens for conventions and likely file roles
- After detection, populate the `## Context7 Assist` section in `index.md` if the calling agent has access to context7 or an equivalent local-docs source. Add 2-4 canonical-docs snippets per detected framework so later enrichment in `02/03` can ground claims in canonical docs rather than memory. This is opt-in per agent runtime — bash `scanman scan` itself does not invoke context7 (Claude-specific MCP).
- Never let framework conventions override what the source code actually proves

### 1. Inventory the system
- Create `00-file-inventory.md` first so coverage is explicit
- Map repo structure, packages, entrypoints, CLIs, plugins, services, and state directories
- Include a selective ASCII repo tree of architecturally relevant paths
- Identify which parts are core vs adapters vs tooling vs demos
- Mark seen vs deferred areas so later agents know what was actually reviewed
- Treat bootstrap inventory as provisional until enriched with targeted manual review

### 1b. Build a dependency map
- Create `00b-dependency-map.md`
- Capture package-level dependencies, important imports, and internal coupling
- Include at least one package dependency graph and one file/module import graph in ASCII
- Distinguish architectural dependencies from incidental ones

### 2. Reconstruct runtime flow
- Trace the main execution path
- Determine how a run/session starts, progresses, pauses, resumes, and ends
- Record data flow, control flow, persistence, and external dependencies
- Include ASCII data-flow charts: one high-level and one more detailed path
- Capture the main functions/methods that actually drive the system and summarize how they are used
- Include a pseudocode-style reconstruction for the most important runtime paths so another agent can understand behavior without rereading every file
- For strict scans, only put `verified` claims into the main pseudocode path; move everything else to `inferred` or `unknown`

### 2a. Runtime proof workflow
- Start from concrete entrypoints, not from broad imports alone
- For each entrypoint, trace the verified call path downward into the first real coordinators and side-effect boundaries
- Record callback/event loops explicitly; many systems are driven more by callbacks than by straight-line calls
- Keep a separate list of `verified call paths`, `inferred paths`, and `unknown paths`
- Write pseudocode only after the verified path has been traced from entrypoint to meaningful side effects
- Use import/dependency graphs as support material, not as proof of runtime behavior

### 3. Extract core primitives
- Name the true building blocks
- Example primitive types: run, task, effect, breakpoint, journal event, process, adapter, state cache, approval mode, quality gate
- Separate essential concepts from implementation noise

### 4. Assess risk and bloat
- Note attack surface, dependency risk, shell/network/write behavior, trust boundaries, and supply-chain risk
- Mark overengineering, duplication, and generic surfaces that are unnecessary for the intended target

### 5. Redesign for the target use case
- Translate only the useful primitives into a smaller target architecture
- Prefer local-first, simpler state, explicit approvals, narrower scope, and fewer moving parts
- State clearly what to keep, drop, replace, or simplify

### 6. Capture reusable learnings
- If the method itself proves reusable, save only the sanitized pattern to shared guidance
- Keep repo-specific facts in `local/`

## Enrichment Model
- Keep one canonical doc set per repo under `local/research/repo-distill/<repo-slug>/`
- New passes should primarily enrich the existing docs, not create sibling copies, unless you are intentionally preserving a before/after snapshot or comparing methodology revisions
- Mark each file clearly as `bootstrap`, `manually enriched`, or `verified` where relevant
- Do not let checklist completion imply certainty that the text itself does not support
- Prefer raising confidence in-place over creating pass-sprawl
- Use claim labels explicitly when precision matters:
  - `verified` — directly supported by read source files
  - `inferred` — strong reconstruction from surrounding evidence, but not directly proven line-by-line
  - `unknown` — not yet proven; do not fill with guesses

## Checklist

### Bootstrap
- [ ] File inventory exists
- [ ] Dependency map exists
- [ ] Seen vs deferred coverage is explicit
- [ ] System map exists
- [ ] Repo tree included
- [ ] File/module relationship graph included
- [ ] Package dependency graph included
- [ ] File/module import graph included
- [ ] Bootstrap-only claims are labeled as such

### Strict runtime
- [ ] Runtime flow reconstructed
- [ ] Data-flow charts included
- [ ] Entrypoints identified
- [ ] Verified call paths captured
- [ ] Main functions/methods and their usage captured
- [ ] Pseudocode-style reconstruction included for key flows
- [ ] Main pseudocode path is `verified`-only or explicitly labeled otherwise
- [ ] Unproven claims are marked `inferred` or `unknown`
- [ ] Manually verified conclusions are distinguishable from generated scaffolding

### Strict distill
- [ ] Core primitives named
- [ ] Risks and ballast identified
- [ ] Redesign proposed
- [ ] Reusable learnings separated from repo-specific notes

### Complete
- [ ] `03-core-primitives.md` is materially filled
- [ ] `04-risk-and-bloat.md` is materially filled
- [ ] `05-redesign-v1.md` is materially filled
- [ ] Remaining unknowns are explicit and bounded
- [ ] **`bash scripts/scanman-validate.sh <workspace-dir>` exits 0** (mandatory gate)
- [ ] Scan can be presented as complete enough for the user’s purpose

## Pitfalls

- Don’t jump from code reading straight to implementation
- Don’t confuse wrappers/adapters with the actual engine
- Don’t preserve generic surfaces that the target product does not need
- Don’t save repo-specific facts into shared notes
- Don’t stop at bootstrap and call it a finished scan

## Confidence Rubric

Use one of these labels consistently:
- `sampled` — small subset only
- `selective` — focused but incomplete architectural coverage
- `focused` — most critical architectural areas reviewed
- `broad` — most relevant areas reviewed, some deep areas deferred
- `near-exhaustive` — almost all materially relevant areas reviewed

## Reproduction-Spec Mode (v0.6)

A second operating mode complementary to (not a replacement for) the default `focused`/`complete` mode.

### When to use vs focused mode

| User intent | Mode |
|---|---|
| "Understand this repo" (architecture, primitives, runtime flow) | `focused` (default — produces `00`–`05` canonical layout) |
| "Distill this repo so a blind rebuilder can reimplement it in any language" | `reproduction-spec` (produces per-primitive `DISTILLATE/<module>.md`) |
| "Document this for AI-assisted rebuild" | `reproduction-spec` |
| Unclear | `focused` (back-compat default) |

The two modes are **complementary**. A serious scan often wants both: `focused` for system-level understanding, `reproduction-spec` for module-by-module blind rebuild. Outputs land in non-overlapping subdirectories under the same canonical workspace.

### The four archetype templates

Reproduction-spec mode selects a template per primitive based on its archetype. All four share the same 12-section base shape; specializations document which sections they ADD, OVERRIDE, or REPURPOSE.

| Archetype | Detection heuristic | Template |
|---|---|---|
| `data-only` | type definitions + constants; no public functions; no FSM state | `templates/repro-spec/data-only.md` |
| `state-machine` | enum representing state + at least one "step/feed/tick" function that dispatches on state | `templates/repro-spec/state-machine.md` |
| `host-export` | `extern "C"` / `#[no_mangle]` / `WASM export` / FFI shim with cross-language ABI surface | `templates/repro-spec/host-export.md` |
| primitive (default) | anything else with public API and runtime behavior | `templates/repro-spec/primitive.md` |

Primitives that straddle archetypes (e.g. a state-machine exposed over an FFI boundary) pick the more constrained template (host-export wins over state-machine) and inline whatever extra sections are still needed.

### How to invoke

```bash
scanman init --mode=reproduction-spec <slug> <repo>
```

Or via the bash skill scripts: `bash scripts/scanman-init.sh --mode=reproduction-spec <slug> <repo-path>`.

### Backward compatibility

Reproduction-spec is additive and opt-in. The default mode (when `--mode` is omitted) remains `focused` and the v0.5 `00`–`05` workflow is unchanged. Existing workspaces are unaffected. The validation gate applies per-mode workspace structure (since v0.6.1): `--mode=focused` checks the `00`–`05` artifacts, `--mode=reproduction-spec` checks `index.md` + `LEARNINGS.md` + `DISTILLATE/*.md` gates — pass the mode explicitly; there is no auto-detection (candidate for v0.7).

### Playbook

The full 6-phase agent runbook (init → inventory + archetype → template scaffold → per-file distillation → validate → optional blind-rebuild) lives in `SCANMAN_REPRO_SPEC_PLAYBOOK.md` next to this file. It is agent-agnostic and includes the learning-capture protocol, gate failure recovery table, and an optional multi-agent parallel-dispatch pattern for large repos.

## Versioning

### Sources
- Source of truth: `system/skills/scanman/VERSION` (plain text, machine-readable)
- Per-version history: `system/skills/scanman/CHANGELOG.md`

### Stability and policy
- Pre-1.0 — the method is still moving.
- Stay in the `0.0.x` range until the workflow, evidence standard, templates, and helper scripts are judged truly stable.
- Move out of `0.0.x` only when Scanman feels operationally stable and its output contract is intentionally locked tighter.

### When to bump
Bump `0.0.x` when the method bundle changes materially:
- `system/skills/scanman/SKILL.md`
- `system/skills/scanman/CHANGELOG.md`
- `templates/repo-distill-*.md`
- `scripts/scanman-*.sh`

Each repo-distill workspace records the Scanman method version used to initialize it (`index.md`'s `Scanman method version` field). That lets later agents compare analyses fairly as the method evolves.

### Commands
- Show current version: `bash scripts/scanman-bump-version.sh --show`
- Patch bump in `0.0.x`: `bash scripts/scanman-bump-version.sh patch`
- Validate release metadata: `bash scripts/scanman-release.sh check`
- Build a portable bundle: `bash scripts/scanman-build-release.sh`

### Release contract
A Scanman release is a named method snapshot consisting of the skill spec (this file), templates, helper scripts, and CHANGELOG history. A release must also preserve the user contract: minimal repo/path input should still drive Scanman toward a complete-enough canonical output, not just a bootstrap scaffold.

### Sharing
If Scanman is shared outside agentBrain, share the bundle at the same version:
- `system/skills/scanman/`
- `templates/repo-distill-*.md`
- `scripts/scanman-*.sh`

The build helper packages these as a portable zip. The bundle can later become a standalone package/repo without losing version continuity.

### Independence from agentBrain
Scanman is part of agentBrain, but its method may evolve independently. Treat `system/skills/scanman/` as the canonical method bundle. If Scanman is ever extracted as a standalone package, preserve the same version/changelog discipline so repo analyses remain comparable.

## Verification

A good distillation should let another agent answer:
- What files/areas were actually reviewed?
- Which parts are bootstrap-inferred vs manually verified?
- Which claims are `verified`, `inferred`, or `unknown`?
- What were the entrypoints and verified call paths?
- How complete/confident is the scan?
- What is the system really doing?
- Which main functions/methods drive that behavior?
- Which concepts are essential?
- Which parts are optional or harmful?
- What is the smallest safer version worth building?
