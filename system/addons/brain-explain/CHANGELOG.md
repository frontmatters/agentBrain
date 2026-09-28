---
date: 2026-06-25
type: system
tags: [addon, brain-explain, changelog]
id: 684108ae-42eb-5e61-a3e7-7aabdd5971e2
---

# Changelog

All notable changes to this addon are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this addon adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-09-06

### Changed

- Paths under the vault are spelled `vault/…`; the `local/` alias is no longer assumed (setup no longer creates it). Card items that wrap keep their continuation lines.

## [0.1.1] - 2026-07-26

### Added

- `CHANGELOG.md` itself, per the new agentBrain addon changelog convention
  (Keep a Changelog + SemVer, see `system/addons/README.md`).

## [0.1.0] - 2026-06-25

### Added

- Retroactively backfilled entry — this changelog was introduced after the
  addon already existed at this version. See `README.md` and this repo's
  git history (`git log -- system/addons/brain-explain/`) for the actual change
  history prior to this file's creation.
