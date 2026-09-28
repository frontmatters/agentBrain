---
date: 2026-06-10
type: system
tags: [addon, extract-learnings, changelog]
id: 69f253bb-85f8-5929-a71e-0a7577d3a133
---

# Changelog

All notable changes to this addon are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this addon adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.3] - 2026-09-07

### Fixed

- The core imported `callModel` from youtube-digest, which is not in the release payload,
  so on every fresh install the precompact hook loaded nothing and no learning was ever
  extracted. It imports the shared `@agentbrain/lib/model-call` now.

## [0.1.2] - 2026-09-06

### Fixed

- Learnings were written to `<checkout>/local/learnings/extracted/`, beside the vault
  link. They land in `vault/learnings/extracted/` now (`local/` on an older install).

## [0.1.1] - 2026-07-26

### Added

- `CHANGELOG.md` itself, per the new agentBrain addon changelog convention
  (Keep a Changelog + SemVer, see `system/addons/README.md`).

## [0.1.0] - 2026-06-10

### Added

- Retroactively backfilled entry — this changelog was introduced after the
  addon already existed at this version. See `README.md` and this repo's
  git history (`git log -- system/addons/extract-learnings/`) for the actual change
  history prior to this file's creation.
