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

## 1. Doel van deze mode

scanman heeft twee operating modes:

| Mode | Output | Use case |
|---|---|---|
| `focused` (v0.5, default) | Architectuur-distillaat — smallest set van concepten | "begrijp deze repo" |
| `reproduction-spec` (v0.6) | Rebuildable spec — rijk genoeg om in willekeurige taal te herbouwen zonder de originele source | "destilleer zo dat AI/dev het kan rebuilden" |

Trigger op user intent:
- "begrijp deze repo" → `focused`
- "destilleer zo dat hij rebuildbaar is in taal X" → `reproduction-spec`
- "documenteer voor AI-rebuild" → `reproduction-spec`
- Onduidelijk → `focused` (back-compat)

## 2. Pre-flight checks

- [ ] `zig`, `rustc` of target-taal compiler beschikbaar (voor optionele blind-rebuild fase)
- [ ] Target repo lokaal: `~/.opensrc/<provider>/<org>/<repo>/<branch>/` (anders eerst `/opensrc fetch <pkg>`)
- [ ] `~/agentBrain/scripts/uuid5-gen.sh` executable
- [ ] `~/agentBrain/system/skills/scanman/` aanwezig met SKILL.md, VERSION, templates/repro-spec/

Binary detection:
```bash
SCANMAN_BIN=""
if command -v scanman &>/dev/null; then
    SCANMAN_BIN="scanman"
elif [ -x "$HOME/agentBrain/system/skills/scanman/rust-impl/target/release/scanman" ]; then
    SCANMAN_BIN="$HOME/agentBrain/system/skills/scanman/rust-impl/target/release/scanman"
elif [ ! -x "$HOME/agentBrain/system/skills/scanman/scanman-validate.sh" ]; then
    echo "FATAL: geen scanman binary EN geen bash mirror — installeer scanman of herstel ~/agentBrain/system/skills/scanman/" >&2
    exit 1
fi
# SCANMAN_BIN leeg = bash mirror actief (scanman-*.sh wrappers).
```

**Aanroep-conventie**: de `scanman-*.sh` wrappers zijn de canonieke entry-points
in alle fasen hieronder. Ze detecteren de Rust binary zélf (via
`_scanman-lib.sh::detect_scanman_bin`) en delegeren automatisch — de
bash-aanroepen zijn dus altijd correct, mét of zónder binary. `$SCANMAN_BIN`
direct aanroepen is een optionele shortcut, geen vereiste.

## 3. De 6 fasen

### Fase 0 — Init workspace

**Slug derivation**: `slug=$(basename <repo-path> | tr '[:upper:]' '[:lower:]')`
OF een user-supplied argument. Expected pattern: kort, lowercase, kebab-case —
bv. `wterm`, `react`, `next-js`. De slug bepaalt het workspace-pad
`local/research/repo-distill/<slug>/` en de UUID5-seeds van alle distillates,
dus kies hem vóór init en wijzig hem daarna niet meer.

```bash
bash ~/agentBrain/system/skills/scanman/scanman-init.sh \
    --mode=reproduction-spec <slug> <repo-path> [goal]
# of via Rust:
$SCANMAN_BIN init --mode=reproduction-spec <slug> <repo-path>
```

Expected output:
- Workspace: `~/agentBrain/local/research/repo-distill/<slug>/`
- Files: `index.md` met `mode: reproduction-spec` veld, `00-file-inventory.md` skeleton
- Subdir: `DISTILLATE/` (leeg)
- Subdir: `LEARNINGS.md` (skeleton — zie §5 hieronder)

### Fase 1 — Inventory + archetype-classificatie

```bash
bash ~/agentBrain/system/skills/scanman/scanman-scan.sh \
    --mode=reproduction-spec <workspace>
```

Per source-file: bepaal archetype via heuristieken. De kolom **Universal
pattern** is leidend (taal-onafhankelijk); de kolom **Detectie (Zig-voorbeeld)**
illustreert hoe dat patroon er in één concrete taal uitziet:

| Archetype | Universal pattern | Detectie (Zig-voorbeeld) | Template |
|---|---|---|---|
| `data-only` | constants + type-definities, **no methods on the type**, geen module-state | alleen `pub const X` + `pub const Y = struct {}` zonder methods/module-state | `data-only.md` |
| `state-machine` | **enum + dispatcher fn** (state-enum, event/action-enum, handler-dispatch) | `State = enum`, `Action = enum`, handler-dispatch | `state-machine.md` |
| `host-export` | **extern/export functions OR module-level mutable state** (FFI/ABI-grens) | `extern fn`, `export fn`, module-level `var X = ...` | `host-export.md` |
| `primitive` | **default fallback** voor mixed data+logic modules | — | `primitive.md` |

Output: `00-file-inventory.md` krijgt extra `archetype` kolom.
Manual override: edit `00-file-inventory.md` na inspectie.

### Fase 2 — Template instantiation

Per source-file in inventory:
```bash
cp ~/agentBrain/system/skills/scanman/templates/repro-spec/<archetype>.md \
   <workspace>/DISTILLATE/<basename>.md
# Frontmatter UUID5 setten
NEW_UUID=$(bash ~/agentBrain/scripts/uuid5-gen.sh \
   "local/research/repo-distill/<slug>/DISTILLATE/<basename>")
# Replace 'id:' line in nieuwe file met $NEW_UUID
```

Of via Rust binary: `$SCANMAN_BIN scaffold-distillates <workspace>`

Resultaat: `<workspace>/DISTILLATE/<file>.md` per source-file, template-ready.

### Fase 3 — Per-file distillation (het LLM-werk)

Voor elke `<workspace>/DISTILLATE/<file>.md`:

1. Lees source-file + dependencies voor context (mag in deze fase)
2. Vul elke sectie volgens per-template instructies
3. Critical disciplines (gehandhaafd door validate gate):
   - §3 constants: expliciete **values**, niet alleen names (G1)
   - §4 types: declare `**Memory layout**: regular|extern|packed` (G10)
   - §6 invariants: genummerd `I1..In`, met check-trigger (G2)
   - §7 pseudocode: **LANGUAGE-AGNOSTIC** — géén Zig `*|`, géén Rust `?` (G7)
   - §10 anchors: label `source-extracted` of `synthetic` + pure-module/cross-module (G5, G11)
   - §10 minimum: ≥1 anchor per public function als synthetic (G8)
   - §12 abbreviations: **GEEN substitute** voor full dep distillates (G13)

**Cross-file synthesis voor §8 (Caller contracts)** — §8 bevat informatie die
NIET in de module-source staat (wie roept aan, wanneer, met welke pre-condities)
en is empirisch het krachtigste distillaat-veld. Recipe:

```bash
grep -rn "<module_name>" <repo-path> --include="*.<ext>" | grep -v "<module_file>"
```

Neem de **top-3 call-sites** (meest frequente of meest constraining) en schrijf
**1 bullet per site**: caller-functie + `file:line`, pre-conditie, post-call
expectation, trigger-frequency. Tabelvorm:

| Trigger site | Condition | Args | Notes |
|---|---|---|---|
| `Terminal.doLinefeed` | not on alt-screen AND scroll_top == 0 | row + cols | row about to scroll off |

Skip §8 nooit voor "single caller" modules — zelfs één caller heeft post-call
discipline (zie G9).

### Fase 4 — Validate

```bash
bash ~/agentBrain/system/skills/scanman/scanman-validate.sh \
    --mode=reproduction-spec <workspace>
# of: $SCANMAN_BIN validate --mode=reproduction-spec <workspace>
```

Exit 0 = pass. Exit 1 = fail met **actionable error messages** per file (`file:line` + gate ID + fix-hint).

### Fase 5 — Optional blind-rebuild test (sterkste bewijs)

Aanbevolen voor high-confidence completion:

1. Kies kleinste distillaat (typisch data-only)
2. Maak test-project in target-taal (apart dir, géén link naar source) —
   minimal bootstrap: zie Appendix A
3. Rebuild module vanuit ALLEEN het distillaat (sluit source, geen grep op original)
4. Run tests
5. Elke "ik moet gokken / ik moet bron checken" → `LEARNINGS.md` entry

Dit is **HET bewijs dat distillaat rebuildable is**. Zonder fase 5 weet je niet
zeker dat fase 4 voldoende was — gates checken vorm, blind rebuild checkt substantie.

### Fase 6 — Complete

Voorwaarden om workspace `status: complete` te markeren:
- Fase 4 validate exit 0
- `index.md` `status: complete`
- (Aanbevolen) Fase 5 succesvol op ≥1 module
- `LEARNINGS.md` bijgewerkt

## 4. Error recovery — gate failures

Volledige gate-lijst G1–G13. Failure messages volgen het canonieke format
`<file>:<line>: G<x>: <beschrijving>. Fix: <hint>`.

| Gate | Failure | Fix | Sample failure message |
|---|---|---|---|
| G1 | Constant zonder Value kolom | Voeg `Value` toe aan §3 tabel | `DISTILLATE/cell.md:42: G1: constant 'MAX_COLS' zonder Value. Fix: voeg expliciete value toe aan §3 tabel` |
| G2 | Invariant zonder check-trigger | Voeg `When checked` kolom | `DISTILLATE/parser.md:88: G2: invariant I3 zonder check-trigger. Fix: vul 'When checked' kolom` |
| G3 | Cross-module anchor ontbreekt waar §10 die verwacht | Schrijf de ontbrekende anchor, gelabeld `source-extracted` of `synthetic` | `DISTILLATE/scrollback.md:160: G3: §10 verwijst naar cross-module anchor die ontbreekt. Fix: schrijf anchor met provenance-label` |
| G4 | — | **no fix — out of scope voor v0.6**; gate niet geactiveerd | — |
| G5 | Anchor zonder provenance-label | Voeg `(source-extracted)` of `(synthetic, pure-module)` | `DISTILLATE/parser.md:201: G5: anchor zonder provenance-label. Fix: voeg '(source-extracted)' of '(synthetic, pure-module)' toe` |
| G6 | State-machine zonder state-reset matrix (§4b) | Voeg `## State-reset matrix` toe: per entry-helper welke state-velden hij reset/preserveert | `DISTILLATE/parser.md:95: G6: state-machine distillate lacks '## State-reset matrix' section. Fix: add a section enumerating each entry-helper and which state fields it touches` |
| G7 | Taal-specifieke pseudocode | Vervang door agnostic ops + behavior in prose. Before: `if (buf.pop()) \|item\| return item.?;` → After: `if buffer non-empty: remove and return last element (guaranteed non-null by I2)` | `DISTILLATE/cell.md:77: G7: Zig-specifieke syntax in §7 pseudocode. Fix: herschrijf language-agnostic` |
| G8 | Public function zonder anchor | Schrijf synthetic anchor per Public API entry | `DISTILLATE/scrollback.md:180: G8: public function 'push' zonder anchor. Fix: schrijf synthetic anchor in §10` |
| G9 | Post-dispatch state visibility ontbreekt | Documenteer in §8 welke state-velden de caller ná dispatch leest en tot wanneer ze geldig blijven | `DISTILLATE/parser.md:140: G9: state-mutating call zonder post-dispatch contract. Fix: voeg 'Caller reads X after dispatch, before next feed()' toe aan §8` |
| G10 | §4 type zonder Memory layout | Voeg `**Memory layout**: regular\|extern\|packed` | `DISTILLATE/cell.md:51: G10: type 'Cell' zonder Memory layout declaratie. Fix: voeg '**Memory layout**: extern' toe` |
| G11 | Data-only met runtime anchor | Vervang door compile-time layout anchor | `DISTILLATE/cell.md:139: G11: data-only anchor zonder 'compile-time' kind. Fix: voeg '(synthetic, pure-module, compile-time)' toe` |
| G12 | — | **no fix — out of scope als gate**; constant-groupings zijn een documentatie-conventie in §3 (zie templates), geen blokkerende check | — |
| G13 | §12 abbreviation als substitute | Verwijs naar `DISTILLATE/<dep>.md` ipv abbreviated spec | `DISTILLATE/terminal.md:230: G13: §12 bevat abbreviated spec van dep 'parser'. Fix: verwijs naar DISTILLATE/parser.md` |

**Enforcement-dekking**: de bash mirror blokkeert op G1/G7/G10 (G13 als warning);
de Rust binary dekt G1, G2, G6 (state-machine), G7, G8, G10, G11, G13 (G9 als
warning). Gates zonder automatisering (G3, G5 in bash) zijn manual-review punten
tijdens fase 3 — de validator-output benoemt ze expliciet als WARN.

## 4a. Optional: Pi peer-review na Fase 4 (agent-comprehension test)

Voor extra volwassenheidsbewijs van het distillaat (niet alleen vorm-correct
maar ook agent-agnostisch begrijpelijk):

```bash
bash ~/agentBrain/system/skills/peer-review/bin/peer-review \
    <workspace>/DISTILLATE/<module>.md \
    --to=any --wait=120 \
    --focus="Could a competent LLM agent rebuild this module in <target-language> using ONLY this distillate? Identify ambiguities or missing instructions. Verdict: READY | NEEDS-REVISION | UNCLEAR."
```

Twee peer-reviews met verschillende LLMs (e.g. gpt-oss:120b + minimax-m3) levert
**convergence-evidence**: issues die beide modellen onafhankelijk vinden zijn
sterk signal, single-model findings zwakker.

**KRITIEK**: ná peer-review **ALTIJD het herevaluatie-protocol** uit
`~/agentBrain/system/skills/peer-review/SKILL.md` "Post-review herevaluatie"
sectie volgen. Peer-review is niet onfeilbaar — false positives komen voor.
Niet blindelings overnemen.

## 5. Learning capture protocol — VERPLICHT

**Dit is de feedback-loop die scanman volwassen maakt.** Elke v0.6 execution
produceert empirisch bewijsmateriaal. Negeer dit niet.

Tijdens fase 3-5: maintain `<workspace>/LEARNINGS.md`:

```markdown
# Learnings — <repo-slug> reproduction-spec execution

## Distillate-writing observations

- File X took N minutes, template archetype <Y> was correct/incorrect
- Section §Z was confusing because... → suggest template improvement
- Caller-contract synthesis (§8) required reading N other files

## Gate-failures encountered

- G<x> at file <f> line <n>: <description> → fix applied: <how>
- Pattern: G<x> repeatedly failed because template instruction was unclear

## Blind-rebuild gaps (fase 5)

- Had to guess: <what> — distillate section <s> missed: <field>
- Had to peek at source: <which file> — distillate section <s> incomplete

## Recommendations for scanman v0.7+

- Template change: ...
- Gate addition: ...
- Process clarification: ...
```

Na completion (fase 6): commit naar 
`~/agentBrain/local/learnings/scanman/scanman-v0-6-execution-<date>-<repo>.md`
met UUID5 frontmatter via `scripts/new-note.sh learning ...`.

**Reden**: v0.6 is een eerste implementatie. Iedere execution is data voor v0.7+.
Zonder dit loop is scanman stuck op zijn eerste ontwerp.

## 6. Multi-agent parallel dispatch pattern (optioneel)

Voor grote repos (50+ source files), parallelliseer fase 3:

```
Orchestrator agent (1):
  - Fase 0-2 (init, inventory, archetype, template scaffold)
  - Dispatch sub-agents voor fase 3 (één per source-file of per cluster)

Per-file sub-agents (N):
  - Receives: source file path + DISTILLATE template path + caller-grep results
  - Returns: filled distillate file
  - Schrijft alleen naar zijn eigen DISTILLATE file (geen cross-write)

Orchestrator (vervolg):
  - Fase 4 validate (single-process)
  - Route gate-failures back to per-file sub-agents voor iteratie
  - Optioneel: Pi peer-review via /peer-review skill voor agent-agnostic test
```

Werkt op elke agent-platform: Claude Code `Agent` tool, Pi worker queue, 
Copilot CLI parallel tasks. Het gate accepteert Markdown files ongeacht 
welke agent schreef.

## 7. Validation philosophy

Een reproduction-spec distillaat **IS** de spec. Twee criteria voor "complete":

1. **Vorm-criterium** (fase 4 gate): mechanisch checkbaar. Exit 0 = vorm OK.
2. **Substance-criterium** (fase 5 blind rebuild): empirisch. Tests pass in 
   target-taal = substance OK.

Vorm zonder substance = false confidence. Substance zonder vorm = nutteloos 
voor toekomstige agents. Beide nodig.

Dit verschilt van focused mode waar "complete enough for purpose" een subjectief
judgment is. In reproduction-spec mode is "complete" objectief geverifieerbaar.

### Source-reading discipline

"Rebuildable zonder source" gaat over het **distillaat**, niet over de
**schrijver** ervan:

- **Tijdens distillaat-writing (fase 3)**: de bron consulteren is OK — sterker,
  het is vereist voor spec-extractie (constants, invariants, caller-grep).
- **Het distillaat ZELF** moet rebuildable zijn zonder source-toegang: alle
  informatie die een blind rebuilder nodig heeft staat erin.
- **Fase 5 (blind rebuild)** verifieert dit door de bron expliciet te sluiten:
  geen reads, geen grep op de originele repo tijdens de rebuild.

Er is dus geen contradictie tussen "mag source lezen in fase 3" en "rebuild
without source in fase 5" — het zijn twee verschillende rollen (spec-writer
vs. blind rebuilder) met verschillende toegangsregels.

## Appendix A — Blind-rebuild minimal bootstrap

Doel: een kaal test-project waarin fase 5 kan draaien. Dit is bewust het
absolute minimum — volledige language packs (per-taal project-skeletons) zijn
een expliciete v0.7+ non-goal (zie CHANGELOG 0.6.0).

**Target = Zig** (`mkdir rebuild && cd rebuild`):

```bash
zig init                       # genereert build.zig + src/
# src/<module>.zig  ← rebuild target vanuit distillaat
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
# <module>.go ← rebuild target; <module>_test.go met func TestAnchorA1(t *testing.T)
go test ./...
```

Per §10-anchor in het distillaat: schrijf één test. Anchors zijn ontworpen als
direct vertaalbare test-cases — geen extra test-design nodig.

## 8. Related

- `SKILL.md` — scanman overall procedure (alle modes)
- `templates/repro-spec/{primitive,state-machine,data-only,host-export}.md` — 4 archetype templates
- `CHANGELOG.md` — version history
- `~/agentBrain/local/research/repo-distill/scanman-v0-6-template-empirical-validation-2026-05-31` — design research note
- `~/agentBrain/local/research/repo-distill/scanman-handover-2026-05-31` — predecessor session
- `~/Developer/wterm-rebuild-zig/` — empirical validation project (3 archetypes, 26/26 tests)
