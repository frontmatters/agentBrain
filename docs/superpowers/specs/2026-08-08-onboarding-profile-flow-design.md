# Onboarding profile-flow redesign — design spec

Status: proposal, awaiting peer review. Sim: local/tools/onboard-proto/profile-flow-sim.html

## Problem

The model-free onboarding wizard (scripts/onboard-wizard.sh) asks 13 questions.
Several ask for information that (a) the machine can detect at runtime, (b) an
agent can infer better at the moment of use, or (c) does not measurably change
agent behaviour. The intake feels long, and on a fresh machine some questions
(editor) cannot even be answered honestly.

## Design test applied

A question earns its place only if an agent demonstrably behaves differently
because of the answer, AND the answer cannot be detected at the moment of use.

Applied to the current 13 fields:

| field | verdict | reason |
|---|---|---|
| language | KEEP (core) | changes every response; artifactLanguage rides along (conditional) |
| askFirst + autonomy | MERGE (core) | same axis measured twice; one 3-level autonomy question |
| channel + updateMode | MERGE (core) | operational machine config; one question with real channel names |
| os | DROP from wizard | runtime `uname` is always fresher; a stored OS is wrong in a shared vault spanning Mac + Pi |
| editor | DROP from wizard | agents work in the terminal; near-zero behaviour change; unanswerable on fresh installs |
| languages/frameworks | PROFILE | in a repo, package.json is the truth; value is only defaults for NEW projects → profile preselect |
| hosting | PROFILE | consumed when creating repos/remotes; detectable from remotes then; profile preselect |
| verbosity, design, decision | DEFER | soft prompt flavour → /onboard deepening (skip-if-done) |
| scope | unchanged | already /onboard-only, never in the terminal wizard |

## New flow (5 interactions, 3 essential)

1. **Profile** — "What describes you best?" frontend/web · full-stack ·
   systems/CLI · data/AI · maker/Pi · no profile. Preselects tech answers.
   "no profile" falls back to the full current question flow (nothing is lost).
2. **Review screen** — one checkbox list combining detection + profile;
   enter = confirm, toggle what is wrong. Source hierarchy per row:
   **detected > profile suggestion > "(fill in later)"**. Machine facts (OS,
   editor) come from detection only; person facts (languages, hosting) come
   from the profile and hold on an empty machine too.
3. **Language** — default from OS locale (AppleLocale/$LANG → nl_NL ⇒
   Nederlands). artifactLanguage asked only when ≠ English (existing condition).
4. **Autonomy** — merged: careful · balanced (default) · autonomous.
5. **Updates** — merged, using the REAL channel names (no second vocabulary):
   stable (default, asks before updating) · prerelease (asks) · edge (notifies
   at session start) · custom (set channel and apply-mode ask/notify/auto/off
   separately). Choosing edge keeps the existing auto mode-flip to branch.

## Fresh install behaviour

- OS: always detectable, even fresh.
- Editor: nothing found → row shows "none yet", preference written as
  "(fill in later)" (existing pattern); /onboard's skip-if-done contract or a
  later re-run of `brain onboard` fills it once an editor exists. agentBrain
  does NOT offer to install editors (GUI apps are out of scope; the agent-CLI
  menu stays CLIs only — opencode is already there).
- Second machine with a shared vault: check-onboarding gate already skips the
  wizard entirely (preferences exist).

## Single source & compatibility

- `profiles` section added to choices.json; validator asserts every preselect
  value is a real option of the target field. Question texts stay in one place.
- Same preference files, same channel/update mechanics — existing installs are
  untouched; re-onboarding just gets shorter.
- Flowchart (build-onboard-flowchart.py) regenerates from choices.json.
- Wizard keeps: AB_WIZARD_DEFAULTS=1 express path, AB_WIZARD_PLAIN=1 plain
  input, checkbox picker with custom escape on every open list, /dev/tty
  reading, ctrl-D = default.

## /onboard additions (knowledge side)

- **Step 8 "Your world" (optional)**: agent-led intake of devices & services —
  open knowledge belongs with an agent that can ask follow-ups, not in the
  terminal wizard. Writes `local/devices/<hostname>.md` (+ an index.md
  hop-page, hostnames canonical for wikilinks) and
  `local/integrations/<service>.md` from two NEW generic templates:
  `system/templates/device-template.md` and
  `system/templates/integration-template.md`. Privacy rule embedded in both:
  credentials referenced by helper/env/keychain NAME, never by value.
  Skip-if-done: devices index exists → only ask what changed.
- **Closing "teach the loops"**: every onboarding run ends by naming the
  capture skills (/save-learning, /save-troubleshoot, /project-update,
  /capture-tool-info) — the organic loops are where a brain's long-term value
  comes from, not the intake.

## Touches

choices.json (profiles + merges), onboard-wizard.sh, system/skills/onboard/
SKILL.md (profiles note, Step 8, loops closing), system/templates/ (device +
integration templates), scripts/test-onboard-choices.sh (profiles + apply-key
assertions), flowchart regeneration. Estimated size: medium (one session incl.
pty tests for profile / no-profile / fresh / defaults / plain paths).

## Risks / open questions

- Merged updates question must still write both config keys (channel + auto_update).
- Locale detection must never block: unsupported locale → English default, never a question.
- Profile presets are opinions; they must stay editable in the review screen and
  never overwrite an existing personalized install (skip-if-done gate stays first).

## Peer review re-evaluation (2026-08-08, gpt-oss:120b via event-bus)

Verdict NEEDS-MINOR-REVISION, 8 findings. Re-evaluated per protocol:

- [CRITICAL] "dropping OS loses context" → NUANCE/already-addressed: OS stays
  visible and editable in the review screen; only the standalone question goes.
  Runtime detection (uname, command -v brew/apt) is fresher at use time.
- [MAJOR] "askFirst+autonomy are orthogonal" → DISAGREE: the cross-combinations
  are redundant or contradictory ("ask before acting" + "full autonomy" is not
  a coherent preference); a 3-level scale covers the meaningful space. NUANCE
  adopted: the merged answer still WRITES both original preference lines.
- [MAJOR] "channel+updateMode merge blocks stable+auto" → already in design:
  combined UI, both keys written; stable+auto reachable via custom.
- [MINOR] "(fill in later) parsed by scripts" → FALSE POSITIVE: verified —
  no script parses tech-stack.md values (build-space-map excludes it by
  design; check-onboarding does not grep it). The files are agent prose.
- [MINOR] "detection wins when stale" → covered: every review row is editable.
- [INFO] locale en_CA example wrong (en_* → English is correct); mechanism
  adopted: match on language prefix, fallback en.
- [INFO] "warn when preset deviates from detection" → DEFER: over-engineering;
  the review screen IS the deviation view.
- [MINOR] "skip-if-done + shared vault across differing machines" → DISAGREE:
  this design removes machine facts from shared prefs, which fixes exactly
  that staleness. Implementation check kept: local/update/config.json must
  stay machine-local when local/ is a shared vault.

Adopted guarantees: (1) merged answers write all original keys/lines,
(2) review rows always editable, (3) locale prefix-mapping with en fallback,
(4) verify update-config machine-locality under shared vaults.
