---
date: 2026-06-10
type: system
tags: [addon, event-bus, changelog]
id: 2ad546fa-b340-53b0-9cb5-2c4f1829667e
---

# Changelog

All notable changes to this addon are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this addon adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `brain-name`: a unique, readable listener name (`calm-robin`) derived from the
  Claude Code session id or a given key, with a djb2-based adjective-animal generator.
  Two sessions listening as the same agent share a cursor and take each other's
  events; a per-session name ends that. `tests/test-name.sh` pins the output and,
  with `BRAIN_NAME_REFERENCE` set, fails when the word lists drift from a reference.

## [0.3.1] - 2026-07-26

### Added

- `CHANGELOG.md` itself, per the new agentBrain addon changelog convention
  (Keep a Changelog + SemVer, see `system/addons/README.md`).

## [0.3.0] - 2026-06-10

### Added

- Retroactively backfilled entry — this changelog was introduced after the
  addon already existed at this version. See `README.md` and this repo's
  git history (`git log -- system/addons/event-bus/`) for the actual change
  history prior to this file's creation.
