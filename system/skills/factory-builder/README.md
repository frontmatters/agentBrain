---
date: 2026-09-23
type: skill
tags: [skill, factory, release, lanes, promotion, agentbrain]
status: active
id: 70be623f-f42b-50a8-9f64-7ef34d73a194
---

# factory-builder

Scaffold, audit and mature a standalone tool factory: the dev/next/live lane
layout that lets an actively used tool ship releases without breaking the copy
you run every day.

Use it for a standalone CLI, service, integration runtime or product with its own
release lifecycle. Do not create a factory for every experiment, client project,
library or agentBrain addon.

## Lane layout

```text
~/Developer/<area>/<tool>.factory/
├── <tool>-dev/     # work happens here
├── <tool>-next/    # validated candidate
├── <tool>/         # the live lane you actually run
└── releases/       # release evidence
```

A factory is named `<tool>.factory` and lives in its area
(`~/Developer/<area>/mytool.factory`); `factory-doctor.sh` fails on any
other name unless `factory.json` records `"legacyName": "<reason>"`.

Promotion moves a candidate from next to live only after its checks pass, so the
live lane never becomes the place where you debug. `factory-link.sh --check`
requires next's command to answer `--version`; if live does not yet answer it,
the check reports INFO rather than failing.

## Commands

| Script | What it does |
|---|---|
| `factory-check.sh` | Validates a factory layout against the expected lanes. |
| `factory-doctor.sh` | Reports health per lane and fails on command-line secret leaks in any lane. |
| `factory-inventory.sh` | Lists projects and flags which ones deserve a factory. |
| `factory-promote.sh` | Moves next to live, refusing detached, unrelated or dev-unmerged lanes. |
| `factory-registry.sh` | Tracks the known factories. |
| `factory-release.sh` | Cuts a tracked-files-only release and records the evidence. |
| `factory-rollback.sh` | Returns live to the previous release. |
| `factory-test.sh` | Checks lane ancestry and optional language policy, then runs the configured tests. |
| `factory-lane-origin.sh` | Requires live HEAD in next and next HEAD in dev. |
| `factory-language-check.sh` | Checks configured product files against per-language word lists (`bash` + `jq`). |
| `factory-leakscan.sh` | Scans tracked shell, TS, JS and Python files in dev, next and live for variable secrets passed in argv. |

The registry and doctor normalize two layouts: the default `standard` layout
(`lanes` and `releases/`) and an explicit `"profile": "composite"` layout
(`framework.dev/next/live` and `releases.root`). Composite factories can provide
additional station measurements through `obeya.stations`; their own release
tooling stays independent. Unknown profiles fail closed. See `SKILL.md` for the
profile contract. Other commands continue to use the standard layout.

Each script reads `factory.json` for its paths and commands. The generic
`factory-release.sh` reads the next lane's `VERSION`, then its `package.json`
version; products with a different version source use their own release script.
Its manifest records the archive checksum and source, but makes no unverified
claim that arbitrary bundled content contains no personal data. Only tracked files in the next lane and declared satellite repositories enter
its archive; untracked files are omitted. Review release contents before publishing.

## Lane provenance gate

`factory-test.sh` and `factory-promote.sh` require **live HEAD reachable from
next HEAD, and next HEAD reachable from dev HEAD**, in one repository. Check
manually with `bash ~/agentBrain/system/skills/factory-builder/bin/factory-lane-origin.sh .`.
Next and live must also be clean, attached worktrees. `test.sh` runs the
language, lane and leakscan regression suites during the framework doctor; the existing
profile test remains in the doctor's own test list. A live hotfix must
return to next and then dev before validation or promotion;
a next-only change must return to dev. This compares Git ancestry, not where a
human originally typed a commit. The check does not copy files or promote
anything by itself. Product-specific release scripts
outside factory-builder must enforce the same route (for example with `--ff-only`).

## Language gate (opt-in)

To prevent non-English CLI help, errors or reports from shipping, add a scoped
`languageCheck` block to `factory.json`:

```json
"languageCheck": {
  "language": "en",
  "paths": ["src/cli.ts", "src/commands/report.ts"]
}
```

`paths` are exact files relative to the product lane. The release gate
(`factory-test.sh`) checks the **next** lane before its tests; run
`bash ~/agentBrain/system/skills/factory-builder/bin/factory-language-check.sh --factory . --lane dev`
during development. The default `languages.json` has target `en` with separate
Dutch, German, French, Portuguese, Spanish, Italian, Polish, Turkish, Russian,
Chinese, Japanese, Korean, Arabic and Hindi forbidden-word lists. For another target or
vocabulary, set `"wordList": "path/to/languages.json"` (relative to the
factory root). Use the same schema: `{ "fr": { "forbidden": { "en": ["Examples"] } } }`.
Only nominate non-localized output files: do not scan translations, fixtures or
user content. This heuristic catches known words, not every foreign sentence;
product-level tests should also assert rendered CLI help and error messages.
An unconfigured factory is unchanged; a configured missing file or word list
fails closed.

## Notes

The scripts target bash 3.2, the version macOS ships. They therefore read command
output with a `while read` loop instead of `mapfile`, which bash 4 introduced.
The source checkout's `check-bash32.sh` enforces this.

See `SKILL.md` for the full workflow, including when a project has earned a
factory and when it has not.
