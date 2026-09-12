---
date: 2026-07-26
type: system
tags: [addon, changelog, hallmark]
id: 4440c2e7-b54c-5614-92a9-fa1d0519fae1
---

# Changelog — hallmark (addon registry entry)

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-07-26
### Added
- Registry entry for the vendored Hallmark design skill (upstream `nutlope/hallmark` v1.1.0, MIT, Together AI).
- Vendored copy at `vault/skills/hallmark/` (SKILL.md + full `references/` tree).
- Manifest attribution: `author: nutlope`, `upstream: https://github.com/nutlope/hallmark`, `license: MIT`.
  The registry entry versions independently of upstream — `version:` tracks this
  wrapper (0.1.0), not the vendored skill's upstream 1.1.0.
