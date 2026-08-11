---
date: 2026-05-20
type: system
tags: [pi-agent, extensions, changelog]
id: 14929481-1676-5be9-8eee-5ff217a13e53
---

# Pi Extensions Changelog

## 2026-07-26

- `pi-cloak`: fixed a false positive found during a vault-review session —
  the bare-long-token-line rule (added earlier the same day) was also
  matching canonical UUIDs (36 chars, hex + hyphens — identical shape to a
  bare secret token), silently redacting `uuid5-gen.sh` output, which every
  note ID in this vault depends on. Added an explicit UUID-shape exception
  before the redaction rule.
- `pi-cloak`: **correction** to the same-day env-secret hook — empirically
  verified it did NOT catch the real leak it was built for. Root cause: a
  `bash` tool call runs in a child process; anything it `export`s is
  invisible to Pi's own `process.env` once the call returns (env only flows
  parent->child, never child->parent), so exact-matching against Pi's host
  env structurally cannot see a secret a bash subprocess fetches-and-prints
  itself. Added `pi-cloak/lib/secret-shapes.ts`: content-only detection
  (bare long-token lines, known token prefixes, generic 32-64 char hex
  anywhere in text) that works regardless of which process produced the
  output. Verified against both real leaks from this session (a bare printed
  token, and one embedded inside a git remote URL) plus negative cases
  (git log --oneline, short SHAs, non-secret env echoes) to confirm no
  regression. Known accepted trade-off: a full-length sha256/git-SHA hash
  will also get redacted (harmless noise, not a security issue).
- `pi-cloak`: added an always-on `bash` tool-result hook that redacts
  currently-exported known-secret env var values (exact-match, not shape-
  guessing) from bash output. Closes the gap where the existing `read`-only,
  file-glob-based redaction could not catch a credential-helper function
  printing its raw value when invoked without capturing its stdout (e.g.
  `source gitea-helper.sh && get_gitea_token` instead of just sourcing).
  New module: `pi-cloak/lib/env-secrets.ts`.
- Hardened `/goal` auto-continuation: a malformed evaluator response is now treated as "not met" instead of crashing `goal_check`, and a `GOAL_MAX_ITERATIONS` backstop abandons a goal that is never verified so the continuation hook cannot loop and burn tokens indefinitely.

## 2026-07-22

- Added `/goal <condition>` with session persistence, transcript-based verification, evaluator usage accounting, automatic continuation, and `/goal clear`.
- Extended `/usage` instructions to include nested LLM usage recorded on Pi tool results, including goal evaluator calls.

## 2026-05-20

- Split large extension files into focused helper modules.
