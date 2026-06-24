---
date: 2026-05-31
type: changelog
tags: [scanman, changelog]
status: active
id: c990a86d-20e7-5aec-9f4e-8376fd8567dc
---

# Scanman Changelog

## Release flow (sticky)

Reference for cutting a new Scanman version. Detailed version policy lives in `SKILL.md` ("Versioning" section).

1. Update `SKILL.md` if the method changed
2. Add an entry below with rationale (not just "what" — also "why")
3. Confirm templates and scripts match the documented method
4. Run `bash scripts/scanman-release.sh check`
5. Bump version: `bash scripts/scanman-bump-version.sh patch`
6. (Optional) Build a portable bundle: `bash scripts/scanman-build-release.sh`

A release must preserve the user contract: minimal repo/path input must still drive Scanman toward a complete-enough canonical output, not just a bootstrap scaffold.

## 0.6.1 — 2026-06-10
- **fix-cyclus na cross-model peer-review** (gpt-oss:120b + minimax-m3:cloud, 2026-06-02/03): alle 10 ✅ AGREE findings uit de geclassificeerde matrix (zie `local/projects/scanman-v0-6/index.md`) doorgevoerd in `SCANMAN_REPRO_SPEC_PLAYBOOK.md`. Waarom: het playbook scoorde 6.5/10 op agent-agnostische uitvoerbaarheid; de convergente findings (beide modellen onafhankelijk) raakten precies de gaten die een niet-Claude agent op een niet-Zig repo zouden blokkeren.
  - P0: `<slug>`-derivation gedefinieerd in Fase 0 (was undefined — CRIT).
  - P1: archetype-heuristieken language-portable gemaakt ("Universal pattern" kolom naast Zig-voorbeelden); §4 gate-recovery tabel compleet G1–G13 (G4/G12 expliciet "no fix — out of scope"); "Source-reading discipline" sub-sectie lost de schijnbare contradictie "source lezen in fase 3" vs "blind rebuild in fase 5" op (spec-writer ≠ blind rebuilder).
  - P2: canoniek failure-message format + sample per gate in §4; Appendix A minimal blind-rebuild bootstrap (Zig/Rust/Go — bewust géén language packs, dat blijft v0.7 non-goal); §8 cross-file synthesis grep-recipe (top-3 call-sites, 1 bullet per site).
  - P3: §2 fail-fast als binary én bash mirror ontbreken; aanroep-conventie gedocumenteerd (wrappers delegeren zelf — `$SCANMAN_BIN` is optionele shortcut, geen vereiste); Fase 4 commando kreeg ontbrekende `--mode` flag; G7 before/after voorbeeld.
- **fixed Rust workspace-mode bug** (gepromoveerd uit "Andere open items" — functioneel defect, zwaarder dan de doc-fixes): `scanman validate --mode=reproduction-spec` eiste de focused 00–05 artifacts en faalde dus altijd op pure repro-spec workspaces (bash zei PASS, Rust zei FAIL op identieke input). Nu per-mode workspace structure in `validate.rs`: repro-spec checkt `index.md` + `LEARNINGS.md` + DISTILLATE-gates, focused checkt 00–05. PASS-rapportage per mode gesplitst.
- **new gate: LEARNINGS.md existence** in repro-spec mode (bash + Rust, parity getest): learning capture (playbook §5) is verplicht — een workspace zonder LEARNINGS.md faalt nu de gate i.p.v. silent de feedback-loop te verliezen.
- **bash repro-spec mode delegeert nu naar de Rust binary** indien aanwezig (8 gates i.p.v. 3); de "ALWAYS pure-bash" policy was gebaseerd op de verouderde aanname dat Rust geen DISTILLATE-checks had. Pure-bash blijft de fallback (G1/G7/G10 blocking + LEARNINGS + warnings).
- **SKILL.md correctie**: de claim dat de gate de workspace-mode "auto-detecteert" was onwaar — vervangen door de werkelijke per-mode semantiek; auto-detect genoteerd als v0.7-kandidaat.
- **verificatie**: wterm-rebuild-zig workspace PASS via Rust, bash-delegatie én pure-bash fallback; negatieve test (workspace zonder LEARNINGS.md) faalt in beide implementaties; `zig build test` groen (26/26 blind-rebuild tests).

## 0.6.0 — 2026-05-31
- **added `reproduction-spec` operating mode** (v0.6) — generates per-primitive distillates rich enough for a blind rebuilder to reconstruct each module in any systems language without consulting the original source. Output lands in `local/research/repo-distill/<repo-slug>/DISTILLATE/<module>.md` (parallel to the canonical `00`–`05` layout), one file per primitive.
- **new templates directory**: `templates/repro-spec/` with 4 archetype templates: `primitive.md` (base, 12-section shape), `state-machine.md` (adds §4a state enum, §4b event/action + reset matrix, §7a transition table), `data-only.md` (overrides §5/§6/§7 as "n.v.t.", repurposes §10 anchors as compile-time-layout), `host-export.md` (replaces §5 with §5a Export ABI + §5b host-managed state, extends §8 with cross-language boundary contract).
- **template selection heuristic**: archetype detected per primitive (data-only / state-machine / host-export / default primitive). Specializations all inherit the 12-section base shape from `primitive.md` and document which sections they ADD, OVERRIDE, or REPURPOSE. Straddling primitives pick the more constrained template.
- **empirical validation**: blind-rebuilt 3 archetypes in Zig from `repro-spec-*` templates alone — Scrollback (6/6 tests), Parser state-machine (13/13 tests, first compile), Cell data-only (7/7 tests, first compile). See research note `local/research/repo-distill/scanman-v0-6-template-empirical-validation-2026-05-31` for the 13 gaps + 14 meta-conclusions that shaped the final template shape.
- **agent execution playbook**: `SCANMAN_REPRO_SPEC_PLAYBOOK.md` (in scanman skill dir) — 6-phase runbook (init → inventory + archetype → template scaffold → per-file distillation → validate → optional blind-rebuild) for any agent (Claude, Pi, Codex, Gemini) to execute reproduction-spec mode end-to-end.
- **backward compatibility**: reproduction-spec is additive and opt-in. Existing `bootstrap` / `strict-runtime` / `strict-distill` / `complete` workflows are unchanged. Default mode remains `focused` (the v0.5 behavior). Invoke the new mode explicitly: `scanman init --mode=reproduction-spec <slug> <repo>`.
- **explicit non-goal for this release**: language packs (per-language project skeletons — `build.zig`, `Cargo.toml`, etc.) are deferred to v0.7+. Reproduction-spec mode itself is the lift; language packs layer on top of a stable mode.
- **minor-bump rationale** (0.0.5 → 0.6.0): this is the first feature release that adds a new operating mode + a new template family + a new output layout. Per the v0.5 versioning policy ("move out of `0.0.x` only when the workflow is intentionally locked tighter"), reproduction-spec is intentional enough to graduate the version line.

## 0.0.5 — 2026-05-31
- **versioning consolidated**: VERSION.md and RELEASE.md deleted; their content folded into `SKILL.md`'s "Versioning" section and this CHANGELOG's "Release flow (sticky)" preamble respectively. Net: 4 metadata files (VERSION + VERSION.md + RELEASE.md + CHANGELOG.md) → 2 (VERSION + CHANGELOG.md). Reduces drift between three near-identical sources and matches the lean `README.md + SKILL.md` pattern used by every other agentBrain skill (survey: `local/research/agentbrain/spec-dedup-survey-2026-05-31.md`).
- **README.md updated** to drop references to the deleted files; "Versioning" content lives in SKILL.md now.
- **added opt-in evidence-link enforcement** (`SCANMAN_REQUIRE_EVIDENCE=1`): when enabled, every `02/03/04` file with `verified` claims must contain at least one source-path reference (e.g. `packages/foo/bar.ts`). Catches the gap where `verified` could be claimed correct-by-luck without an actual source read — the lived experience from the v0.0.4 WTerm self-review. Off by default to avoid breaking workspaces from older method versions. `05` (redesign) is exempted because it refers to primitives from `03` by name, not to source files. Implemented in both `scripts/scanman-validate.sh` (bash) and `system/skills/scanman/rust-impl/` (Rust, byte-identical output). Canonical wterm/ workspace passes with the flag enabled. A stricter `file:line` mode is planned for v0.0.6.
- **added Context7 Assist scaffold**: `templates/repo-distill-index.md` gained an explicit `## Context7 Assist` section with an agent-prompt asking the calling agent to populate canonical-docs snippets per detected framework before deeper enrichment. Agent-agnostic by design — bash `scanman scan` does not invoke context7 itself (Claude-specific MCP); the section header is the hook, the agent runtime fills the body. SKILL.md procedure step 0 ("Detect the stack") updated to reference the new section.

## 0.0.4 — 2026-05-31
- **strengthened the Validation Gate against agent-gaming**: added per-section density check (`SCANMAN_MIN_SECTION_WORDS`, `SCANMAN_MAX_THIN_SECTIONS`) — catches the "fill one table, leave all other sections as template boilerplate" shortcut that the v0.0.3 gate missed
- documented the gaming-vulnerability discovery in the WTerm self-test: an agent (me) passed the v0.0.3 gate with a thin distill, demonstrating that file-totaled word counts are insufficient to enforce "materially filled" sections
- exempt-sections regex (`SCANMAN_EXEMPT_SECTIONS`) for legitimately short sections (`Related`, `Purpose`, `Decision`) — the canonical WTerm workspace passes the strengthened gate; agent-gamed thin distills fail with explicit per-section reasons
- canonical WTerm workspace remains the reference: it passes all v0.0.4 checks including section density

## 0.0.3 — 2026-05-31
- added mandatory **Validation Gate**: `scripts/scanman-validate.sh` is now the sole authority on whether a scan is "complete enough"; exit code 0 = pass, 1 = iterate, 2 = error
- validation enforces: required files exist, no placeholders (`[fill in]`/`TODO`/`TBD`/`FIXME`/`XXX`) in 03/04/05, min word count, min substantial bullets, min claim-labels (`verified`/`inferred`/`unknown`) per file in 02/03/04/05
- SKILL.md now documents the explicit agent loop (bootstrap → enrich → validate → iterate-or-stop) — agent-agnostic, pure bash, works for any agent that can run a shell command
- **fixed showstopper UUID bug** in `scripts/scanman-init.sh`: was passing filename WITH `.md` extension to `uuid5-gen.sh`, but the agentBrain validate-hook expects path WITHOUT `.md`. Mismatched ids caused Claude Code's PostToolUse hook to block every agent edit on a scanman workspace.
- `scripts/scanman-scan.sh` now preserves existing YAML frontmatter when regenerating bootstrap layers (00/00b/01/02) — previously wiped init-generated UUID5s, re-triggering the hook block on every refresh
- `scripts/scanman-scan.sh` now reconciles the `Scanman method version` field in `index.md` from the canonical `VERSION` file on every refresh (fixes stale `0.0.1` reference reported in v0.0.2 handover)
- `scripts/scanman-scan.sh` preserve-detection rewritten: was structural (column-count brittle), now content-based (looks for `verified`/`inferred`/`unknown`/`verified-bet` as a table cell value) — survives template refactors
- templates 03/04/05 gained a `Claim Level` column in all primary tables, matching the canonical workspace shape — visually seeds claim-discipline without weakening the gate
- env overrides for validate thresholds: `SCANMAN_MIN_WORDS`, `SCANMAN_MIN_ITEMS`, `SCANMAN_MIN_BULLET_LEN`, `SCANMAN_MIN_CLAIM_LABELS`
- status fields (`Current phase`, `Completion state`, `Next action`) deliberately preserved across refresh — they describe human-judged enrichment state, not tool state
- end-to-end validation: verified the full agent loop on a fresh WTerm workspace — bootstrap → validate FAIL → agent enriches 03/04/05 → validate PASS, all without manual UUID fixes

## 0.0.2 — 2026-05-30
- strengthened the skill contract so Scanman defaults to iterating toward `complete` output rather than stopping at bootstrap
- added stack detection as phase 0 of the method
- added language/framework-aware assist guidance (e.g. Context7 as helper, never as source of truth)
- expanded the checklist into bootstrap / strict-runtime / strict-distill / complete stages
- added detected-stack fields to the repo-distill index template
- taught `scanman-scan.sh` to record detected languages, frameworks/tooling, and entrypoint candidates in the canonical workspace index
- validated the WTerm scan against the real codebase and used that to tighten the method further

## 0.0.1 — 2026-05-28
- established separate Scanman method versioning inside agentBrain
- added canonical `VERSION.md`
- adopted bootstrap vs manually-enriched vs verified distinction
- added entrypoint-first runtime proof workflow
- added verified / inferred / unknown claim discipline
- added verified-only main pseudocode requirement for strict scans
- improved runtime template with function usage and pseudocode sections
- improved workspace init with per-artifact UUIDs
- added related-linking between scan artifacts
