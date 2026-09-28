---
date: 2026-07-07
type: system
tags: [addon, agentbrain-mcp, changelog]
id: e1ca73d0-16ba-5260-b848-872ad6f77565
---

# Changelog

All notable changes to this addon are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this addon adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-09-06

### Fixed

- The incognito flag was checked at `<checkout>/local/sessions/.incognito`. It is resolved
  through `brainPath` now, so it folds to `vault/` like every other private path.

### Added

- Query expansion (layer A): `vault/.searchmap` synonym map, credited in the fuzzy
  tier and reported as `term→synonym`. Plus layer C: `brain_search` tool description
  now instructs callers to enrich queries with synonyms/domain terms.
- Usage-based ranking: `brain_read` bumps `vault/.access-index.json` (gitignored); a
  recency-decayed count breaks ties in `brain_search` (never filters). `report-stale.sh`
  lists cold notes by a type-aware threshold.

## [0.2.0] - 2026-08-08

### Added

- `brain_status` tool: read-only framework status (active checkout, version
  via git describe, release, update channel/mode/auto_update) for shell-less
  MCP clients. Lifecycle mutations (update, wire, doctor) deliberately stay
  on the host's brain CLI. Every emitted value is validated against a closed
  pattern (enums / version regexes) so tampered on-disk config or tag names
  can never inject free text into model context — covered by tests.

## [0.1.2] - 2026-07-07

### Added

- Retroactively backfilled entry — this changelog was introduced after the
  addon already existed at this version. See `README.md` and this repo's
  git history (`git log -- system/addons/agentbrain-mcp/`) for the actual change
  history prior to this file's creation.
