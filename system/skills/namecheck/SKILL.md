---
name: namecheck
description: >-
  Sweep a product name across every claimable namespace — npm (package + scope),
  GitHub user/org (+ variants like get<name>, use<name>, <name>-ide, <name>-dev),
  Open VSX, VS Code Marketplace, Homebrew (formula + cask), the common TLDs
  (.com .io .dev .ai .app .so .sh .run .tech .tools .co), X/Twitter handle, and
  Reddit. For every TAKEN resource, fetch what's actually behind it (package
  description + maintainer, GitHub bio + company, site <title>, brew formula
  desc, subreddit title) so the user can judge conflict risk — not just "taken".
  Use whenever the user is naming a product, project, package, brand, or
  company; says "is X free", "kan ik X gebruiken", "check name availability",
  "namecheck", "sweep X", "claim X everywhere", "brand X", or is brainstorming
  names and needs to know what's already in use.
argument-hint: <name> [more names...]
license: MIT
---

# namecheck

Use this when a name is being considered for a product, project, package, brand,
or company. The point isn't just "free vs taken" — it's **"if taken, is it a
conflict?"** A name that's free everywhere is great; a name that's free on npm
but `npm i <name>` is a directly competing agent product is a disaster to
discover *after* launch.

## When to use

Triggers (case-insensitive, EN/NL):

- "is X available", "is X free", "kan ik X gebruiken", "X beschikbaar?"
- "namecheck X", "name-check X", "name sweep X"
- "claim X everywhere", "X overal beschikbaar?"
- "brand X", "productnaam X", "merknaam X"
- "what's behind X" (when investigating a specific taken resource)
- Before `/project-update` registration, before claiming domains, before
  printing business cards.

## How to run

```bash
bash ~/agentBrain/system/skills/namecheck/sweep.sh <name> [<name2> <name3> ...]
```

Multiple names in one call produce side-by-side reports — perfect for shortlist
decisions.

## What it checks (and what it returns when TAKEN)

| Namespace | FREE signal | TAKEN returns |
|---|---|---|
| npm package `<name>` | 404 | description, author, homepage, repo, last modified, maintainers |
| npm scope `@<name>` | 404 on `@<name>/core` | owner count / members |
| GitHub user/org `<name>` + variants (`get<name>`, `use<name>`, `<name>-ide`, `<name>-dev`) | 404 | name, bio, company, blog, type (User/Org), public_repos, created_at |
| Open VSX namespace `<name>` | 404 on `/api/<name>` | (rare to be taken; check publisher) |
| VS Code Marketplace | 0 results | matched extension count + names |
| Homebrew formula `<name>` | 404 | full_name, desc, homepage, license |
| Homebrew cask `<name>` | 404 | full_token, name, desc, homepage |
| Domains `.com .io .dev .ai .app .so .sh .run .tech .tools .co` | empty NS + A | fetched `<title>` tag |
| X / Twitter `@<name>` and `@<name>_ide` | 404 | (X blocks scrape; report status only) |
| Reddit `r/<name>` | 404 | title, subscribers, public_description |

## Output format

For each name:

1. **Summary line** — fully free / partial / heavily taken
2. **Tier table** — per-resource ✓ FREE or ✗ TAKEN + one-line "what it is"
3. **Conflict verdict** — is the taken usage related enough to block this brand?
4. **Recommendation** — claim now / consider variant / reject

## Conflict-judgment rubric

When the same name is taken in a context that overlaps the user's intended use:

| Overlap | Verdict |
|---|---|
| Same product class (AI agent, dev tool, IDE, memory) | ⛔ reject — direct conflict |
| Same broader space (software, SaaS) but unrelated function | ⚠️ caution — likely trademark issue in class 9 / 42 |
| Different industry entirely (music, food, geography) | ✅ probably OK, but check trademark DBs |
| Parked domain / dormant GitHub user with 0 repos | ⚠️ speculator — domain buy possible, name still usable on registries |

## Multi-name mode

When the user gives a shortlist, produce a **ranking matrix**:

| Name | npm | GitHub | .com | .io | .dev | .ai | brew | verdict |
|---|---|---|---|---|---|---|---|---|

Then recommend the top pick by **trademark strength × registry cleanliness**.

## Post-sweep follow-ups the agent should offer

- Trademark search (BOIP NL/EU, USPTO US, WIPO) — for top-2 picks
- Defensive-namespace plan (reserve `get<name>`, `use<name>`, `<name>-ide`)
- Domain purchase recommendations (registrar, primary + defensive TLDs)
- Update `claims-registry.md` in the relevant agentBrain project (if a project
  note exists for this naming effort)

## Limitations

- **X / Twitter** blocks scraping; only status code returned. For definitive
  handle availability, the user must try to sign up.
- **VS Code Marketplace** search is keyword-based; exact-publisher availability
  requires attempting a publisher create.
- **Domain DNS-empty** is not 100% proof — a domain can be registered without
  DNS records. For mission-critical names, confirm via `whois` before buying.
- **Trademarks**: this skill does NOT search trademark databases — that needs a
  follow-up with BOIP/USPTO/WIPO. Free-on-registries ≠ unencumbered.

## Examples

```bash
# Single name
bash sweep.sh cortexa

# Shortlist compare
bash sweep.sh encephr encephix mentisio vellio navix
```

## Versioning

- Source of truth: `VERSION` (plain text, SemVer).
- History: `CHANGELOG.md` with dated entries and rationale.
- Bump policy:
  - **patch** — bug fixes, output polish, no new namespaces.
  - **minor** — new namespaces or new output fields (additive).
  - **major** — breaking CLI change or removal of an existing namespace.
- Smoke test before bumping: `bash sweep.sh cortexa` (known-taken) and `bash sweep.sh encephr` (mostly free) — both must complete without errors and produce the tiered report.
- Stays in lockstep with the agentBrain canonical copy at `system/skills/namecheck/` after promotion. Edits happen in one place and sync to the other.

## See also

- `brand-guidelines-maker` — once a name is locked, build the brand kit
- `project-update` — register the chosen name as an agentBrain project
