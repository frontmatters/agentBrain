---
date: 2026-09-22
type: system
tags: [skill, factory, changelog]
id: fd188d7f-8371-52d8-8323-84c4b1e1d17e
---

# Changelog

## [Unreleased]

### Changed

- `factory-release.sh` enforces the rule it was documented with: it refuses unless live is the same commit as next and sits on `vVERSION`. It used to cut an archive from next regardless, so a release chained after a failed promote shipped something live did not have. Test: `bin/test-factory-release.sh`.
- Where a tool keeps its state: `factory.json` declares one variable (`paths`), `~/.config/factories/paths.env` overrides them centrally, and `factory-paths.sh` shows, initialises, loads (rc block and every `<tool>-next`) and moves them (`set` moves the data and never over existing data). `factory-doctor.sh` notes a command without a paths block. Factory discovery moved to `bin/factory-discover.py`, shared by the registry and `factory-paths.sh`. Test: `bin/test-factory-paths.sh`.
- Version gate: `factory-doctor.sh` requires a version of record. `factory-link.sh --check` fails if next does not answer `--version` with a version number; when next passes but live does not, it reports INFO. Tests in `bin/test-factory-link.sh`.
- `<tool>-next` runs a factory's next lane beside the live command (side by side, no switch, no `-dev`). `factory.json` names the command in a `cli` block; `factory-link.sh` writes the wrapper, `factory-doctor.sh` checks it, and a lane that migrates shared data says so on every run (`nextChangesData`). Test: `bin/test-factory-link.sh`.
- A factory directory is named `<tool>.factory` and lives in its area (`~/Developer/<area>/mytool.factory`). `factory-doctor.sh` now fails on any other name unless `factory.json` records `"legacyName": "<reason>"`, and `factory-registry.sh` finds `<tool>.factory` up to `factoryDepth` levels down. Both values live in `layout.json`.

### Fixed

- `factory-registry.sh` listed a git worktree of a factory (a release or LAN branch checked out beside it, carrying the same `factory.json`) as a second factory. It is skipped now.
- `factory-obeya.sh --write` compares generated lines while ignoring only dates, so a moved factory updates its andon path.
- `factory-lane-origin.sh`, `factory-test.sh` and `factory-language-check.sh` read lanes through the shared profile normalizer, so a composite factory is checked by the same dev -> next -> live rule instead of failing on a missing `lanes` block.
- A live lane that is a separate repository is accepted only with `"lanePolicy": {"live": "separate-repo"}`. The deploy records the dev commit it copied (`git config factory.sourceCommit` in the live checkout); that commit must be reachable from next, and every file live tracks must match it, so a change made only in live still fails. Files the deploy leaves out may be missing. Without the policy, or without a recorded source, a separate repository fails.

## [0.4.1] - 2026-09-27

### Fixed
- Public factory examples and fixtures use fictional projects, not real project names or migration history.
- Generic release version discovery uses `VERSION` or `package.json` only; product-specific version files belong in product release tooling.

### Added
- Lane provenance gate for standard factories: next and live must be clean, attached worktrees in the same repository, with live HEAD reachable from next and next HEAD reachable from dev. Tests cover next-only commits, live-only hotfixes, dirty worktrees, detached live, unrelated repositories, and reintegration. `test.sh` wires the lane and language suites into the framework doctor.

## [0.4.0] - 2026-09-27

### Added
- Optional `languageCheck` gate in `factory-test.sh`: scan configured next-lane
  output files against per-language word lists before tests. Includes scoped
  path validation, a custom-list option and a regression suite; unconfigured
  factories still skip the check.
- Standard and composite factory profiles for the registry and doctor, normalized
  by `bin/factory-profile.py`. The composite profile reads `framework` lanes and
  `releases.root`; unknown profiles fail closed. Regression test covers both.
- Andon and obeya. `factory-obeya.sh` builds the obeya, the one place that shows
  a factory, from the measured stations, the hand-kept andon (what is stopped or
  waiting, with its age), the open backlog by priority and rank, and the newest
  log entries. `--init` creates the andon, `--write` the page (vault pages get
  their note id), `--json` the summary. Defaults in `obeya.defaults.json`, every
  value overridable under `"obeya"` in `factory.json`.
- `factory-doctor.sh` notes a missing andon, stale cords and undated cords.
- `factory-registry.sh` adds each factory's andon and next step to the dashboard.

### Added (retiring a factory)
- The spec says where a succeeded factory goes (`R&D/legacy/`, from the new
  `layout.json`) and in which order; `factory-doctor.sh` fails when
  `legacy_factory` is missing or a lane keeps its git history inside it, and
  notes a legacy factory outside `R&D/legacy/` or still in the registry root.

### Fixed
- The CJK language-check path now works under macOS Bash 3.2 with `set -u`;
  a regression test runs the actual system Bash.
- `factory-obeya.sh` reads lanes through `factory-profile.py`, the normalizer
  the doctor and registry use, so a composite factory without `obeya.stations`
  shows its `framework.*` lanes instead of "no lanes".
- `test-factory-profiles.py` runs in the framework doctor; it ran nowhere.
- The registry dashboard shows lanes in plain words (the sha, `dirty`,
  `missing`) instead of emoji.

## [0.3.0] - 2026-09-24

### Added

- `distribution` block in factory.json: format, channel, install, uninstall, maintainer,
  versioning and release. `factory-doctor.sh` notes a factory without one.
- Distribution rules from an initial factory implementation: release only a
  tagged live, test the real installer in an isolated prefix, never replace a development
  install, never remove user data, whitelist what ships.

## [0.2.0] - 2026-09-22

### Changed

- Documented external legacy lanes and the dev → next → live promotion policy.

## [0.1.0] - 2026-09-22

### Added

- Factory minimum structure and mature contract.
- Factory doctor, release gates, registry/dashboard generation and full Developer project inventory.
- Release, promotion, rollback and clean-install gate requirements.
- Public wrapper versus controlled product boundary.
- Factory doctor and validation tooling contract.
