---
date: 2026-05-20
type: system
tags: [pi-agent, extensions, changelog]
id: 14929481-1676-5be9-8eee-5ff217a13e53
---

# Pi Extensions Changelog

## 2026-08-25

- `goal`: SMART gate + resume-recheck, so a goal can actually be verified and
  auto-clears. At set time `/goal <condition>` now runs a 5WH pass (in
  `goal-lib/core.ts`, framework-neutral so any agent can reuse it) that sharpens
  the wording into a verifiable stop-condition. When the goal cannot be made
  verifiable from what the user gave, the extension does NOT activate a vague
  goal; it injects a grill-me directive (the missing facts as questions) so the
  agent sharpens it with the user first. On `session_start` it re-evaluates an
  active goal once and auto-clears it if it was already achieved out of band (in
  another agent, or while the session was idle) — the fix for a goal lingering
  "active" for days. Shared `runEvaluator` backs both `goal_check` and the
  resume-recheck. Every goal set and cleared is appended to a durable JSONL log,
  partitioned per context (a space or a project) so agentBrain can read one project's
  goals in isolation: `~/.agentBrain/goal-logs/<context>/goals.jsonl` (local, unsynced,
  since a condition can carry confidential text). Context = `GOAL_LOG_CONTEXT` (set it
  to a space slug) > the git repo name > `personal`; `GOAL_LOG_PATH`/`GOAL_LOG_DIR`
  override. Cleared events record the outcome (achieved / abandoned / impossible /
  manual / *-on-resume). `/goal log [n]` prints the last n for the current context.
  Path traversal is blocked (`sanitizeContext` drops dots). Covered by unit tests plus
  integration tests that set a goal through the real handler, fire session_start, and
  assert the deregister, the log lines, and per-context placement (21 pass, shipped
  code typecheck clean).
- `goal`: made agent-neutral. The pure logic moved out of `pi-config/extensions/goal-lib`
  to a shared addon `system/addons/goal/lib/core.ts` (zero framework imports); the pi
  extension now imports from there and stays the rich consumer (`/goal`, `goal_check`,
  automated SMART gate, resume-recheck). New `system/addons/goal/bin/ab-goal` is a
  portable CLI so any agent (Claude Code via Bash, cron, a script) can hold one goal per
  context with file-based state (`current.json`) and share the same per-context log.
  Named `ab-goal` to avoid any clash with pi's `/goal`. Core relocation keeps all tests
  green; the CLI is smoke-verified (set/status/met/clear/log).

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
