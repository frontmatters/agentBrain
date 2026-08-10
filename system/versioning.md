---
date: 2026-08-07
type: system
tags: [system, versioning, changelog, conventional-commits, policy]
id: 970b2316-c3ed-5d75-97ee-b9861d982a80
---

# Versioning policy — the "ksc" triad

agentBrain follows three interlocking conventions, together shorthand "ksc":

1. **SemVer** ([semver.org](https://semver.org/spec/v2.0.0.html)) — releases
   are tagged `vMAJOR.MINOR.PATCH`. Breaking framework changes bump MAJOR,
   new capabilities bump MINOR, fixes bump PATCH.
2. **Keep a Changelog**
   ([keepachangelog.com](https://keepachangelog.com/en/1.1.0/)) — every
   notable change lands under `## [Unreleased]` in `CHANGELOG.md` at the
   moment it merges, grouped as Added/Changed/Fixed/Removed. A release moves
   the block under a version heading.
3. **Conventional Commits** — commit subjects use
   `type(scope): imperative summary` (`feat`, `fix`, `docs`, `test`,
   `chore`, `refactor`, `learn` for vault learnings). English, no
   attribution trailers.

## What is NOT automated

Structural tools move files but do not do ksc for you. In particular
`/promote` and `/demote` are pure path-swaps. After promoting an artifact
into `system/`, complete the manual checklist:

1. Fix internal paths in the moved artifact (`local/...` → `system/...`).
2. Add or update the index entry (`system/skills.md` for skills; the addon
   registry for addons).
3. Add a `CHANGELOG.md` entry under `[Unreleased]`.
4. Commit both sides with conventional messages: the public repo (addition)
   and the private vault (removal).

## Release cadence: assemble, do not stream

Releases are **assembled, not streamed**. Features accumulate under
`## [Unreleased]` until they form a coherent, nameable whole; only then does
a version ship. Concretely:

- No version bump per feature. A lone feature waits in `[Unreleased]`.
- A MINOR release bundles related features into a release with a theme (the
  release paragraph under the version heading should be able to say what the
  release *is about* in one sentence).
- PATCH releases are for fixes that cannot wait — not for drip-feeding.
- If `[Unreleased]` has been growing for a while, that is fine. A long
  staging block beats a version festival.

## Scope

This document covers the agentBrain framework repos. Personal per-project
versioning preferences live in the private layer
(`local/preferences/personal/`), not here.
