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
5. Smoke-test: `bash sweep.sh express` (known-taken), `bash sweep.sh zorbelquint` (mostly free) — both must produce a tiered report without errors.

A release must preserve the user contract: a single name argument must produce a complete report with conflict-judgment context for every TAKEN resource, not just a free/taken flag.

## Coverage targets (rolling)

The skill aims to cover every namespace a small software product typically wants to claim. New namespaces get added as the ecosystem evolves.

## 0.2.0 — 2026-08-02

- **new: opt-in trademark clearance** (`sweep-trademark.sh <name>`). Additive — the
  core `sweep.sh` is unchanged (still curl-only, fast, whole-shortlist). The trademark
  registers cannot be curled: TMview is network-blocked, WIPO branddb's API needs an
  ALTCHA proof-of-work + auth token, EUIPO/BOIP are SPA+auth. A real browser solves the
  ALTCHA automatically, so the new script drives the `sitescope` CDP browser through the WIPO
  Global Brand Database (aggregates Benelux/EUIPO/national/Madrid), searches the name,
  and extracts each hit's owner / Nice classes / country / **STATUS** from the DOM +
  a screenshot.
- **why separate, not folded into `sweep.sh`**: keeps the shortlist sweep fast and
  deterministic (no browser dependency), and trademark is a judgement call (active vs
  expired, class overlap, territory) best run once on the finalist, agent-in-loop.

## 0.1.0 — 2026-07-05

- **initial release**. Registry freedom is a poor proxy for "can I actually use this name": a name can be free-ish on registries and still belong to a directly competing product. The skill bakes in **what's behind each TAKEN resource** so conflict-judgment is possible, not just availability.
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

## Roadmap (candidates, unscheduled)

- Add PyPI (Python), crates.io (Rust), Go module path, Packagist (PHP), RubyGems.
- Add Docker Hub namespace.
- Add Mastodon / Bluesky handle probes.
- Add a `--json` output mode for piping into other tooling.
- Caching layer: re-runs within N minutes skip unchanged registries.
