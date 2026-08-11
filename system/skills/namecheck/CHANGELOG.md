---
date: 2026-07-05
type: changelog
tags: [namecheck, changelog]
status: active
id: 80171f32-01b5-5bab-938f-953bae518bdf
---

# namecheck Changelog

## Release flow (sticky)

1. Update `SKILL.md` if the method/coverage changed.
2. Add an entry below with rationale (why, not just what).
3. Confirm `sweep.sh` matches the documented coverage.
4. Bump `VERSION` (SemVer): patch for fixes, minor for new namespaces/coverage, major for breaking CLI changes.
5. Smoke-test: `bash sweep.sh cortexa` (known-taken), `bash sweep.sh encephr` (mostly free) — both must produce a tiered report without errors.

A release must preserve the user contract: a single name argument must produce a complete report with conflict-judgment context for every TAKEN resource, not just a free/taken flag.

## Coverage targets (rolling)

The skill aims to cover every namespace a small software product typically wants to claim. New namespaces get added as the ecosystem evolves.

## 0.1.0 — 2026-07-05

- **initial release**. Born out of the `enceph` product-naming session: registry-freedom turned out to be a poor proxy for "can I actually use this name" — `cortexa` was free-ish on registries but a directly competing agent product (`cortexa.sh` = "The agent for research teams", npm `cortexa` = "Git-inspired context management for LLM agents"). The skill bakes in **what's behind each TAKEN resource** so conflict-judgment is possible, not just availability.
- **coverage on day one**:
  - npm package + `@<name>` scope (with description, author, homepage, last modified, maintainers)
  - GitHub user/org + variants (`get<name>`, `use<name>`, `<name>-ide`, `<name>-dev`) with bio, company, type, repo count, created_at
  - Open VSX namespace
  - VS Code Marketplace keyword search with top hits
  - Homebrew formula + cask (desc, homepage, license)
  - 11 TLDs: `.com .io .dev .ai .app .so .sh .run .tech .tools .co` (with fetched `<title>` when taken)
  - X / Twitter `@<name>` and `@<name>_ide` (status-only — X blocks scraping; noted in SKILL.md limitations)
  - Reddit `r/<name>` (title, subscribers, public_description)
- **conflict-judgment rubric** documented in SKILL.md: same product class → reject; same broader space → caution; different industry → probably OK; parked / dormant → speculator.
- **multi-name mode**: passing multiple names produces side-by-side reports for shortlist decisions. A ranking matrix template is documented but not auto-generated — the agent assembles it from the per-name reports.
- **known limitations** (documented upfront, not deferred):
  - X handle availability requires manual signup confirmation.
  - VS Code Marketplace publisher-existence is keyword-approximate, not exact.
  - DNS-empty ≠ unregistered; mission-critical names need `whois` confirmation.
  - Trademark databases (BOIP/USPTO/WIPO) are intentionally out of scope — that's a follow-up skill or manual step.
- **smoke-tested** against `cortexa` (correctly flagged the agent-product conflict) and a 5-name shortlist (`vellio navix mensor tessera axioma`) where it surfaced 3 direct conflicts (`navix`, `axioma` on npm; `tessera.app` AI partner).

## Roadmap (post-0.1.0 candidates)

- `0.2.0`: add PyPI (Python), crates.io (Rust), Go module path, Packagist (PHP), RubyGems.
- `0.2.0`: add Docker Hub namespace.
- `0.3.0`: add Mastodon / Bluesky handle probes.
- `0.3.0`: add a `--json` output mode for piping into other tooling.
- `0.4.0`: optional trademark-DB check via BOIP public search + USPTO PEDS scraping (best-effort).
- `0.5.0`: caching layer — re-runs within N minutes skip unchanged registries.
