---
date: 2026-09-22
type: spec
tags: [spec]
source: session
version: 0.1.0
id: 42df712f-61a5-51a7-972c-3f970ed4e2da
---

# event-bus SPEC-claims. who is working on what, right now

`brain-claim` records what an agent is about to work on; `brain-claims` reads back who
holds what. A claim is an intention in words plus the paths it expects to touch, with an
expiry. The event log keeps the history; a small projection answers the question a log
cannot answer cheaply: *what is held at this moment.*

For envelope/routing see [[SPEC]]. For filesystem/cursor see [[SPEC-storage]].

**Status**: `IMPL` since 2026-09-23. `brain-claim` and `brain-claims` ship in `bin/`,
pinned by `tests/test-claims.sh`.

---

## Why

Two sessions working one repository can build the same thing twice without either
noticing, and such duplicates rarely share a file path. A claim makes the *intention*
visible before the work starts, which neither a branch, `brain-poll` nor a direct message
does.

## Shape

```bash
brain-claim "one command that runs every gate" \
    --paths=scripts/run-gates.mjs,package.json --ttl=4h
brain-claims                    # what is held right now
brain-claim --release <id>      # done
```

### `brain-claim`

```
brain-claim "intent" [--paths=a,b] [--ttl=4h] [--agent NAME]
brain-claim --release <id>
```

| flag | meaning |
|---|---|
| `--paths=a,b` | comma-separated paths the work expects to touch, relative to the repo |
| `--ttl=<n>h`, `--ttl=<n>m`, `--ttl=<n>` | expiry for this claim: hours, minutes, or bare hours |
| `--agent NAME` | override the resolved identity (see below) |
| `--release <id>` | remove the claim and emit `work.claim.released` |

On success `brain-claim` prints the claim id on stdout.

### `brain-claims`

```
brain-claims [--json] [--repo PATH]
brain-claims --gc
```

| flag | meaning |
|---|---|
| (none) | a table of unexpired claims (`ID AGENT BRANCH INTENT`), or `nothing held` |
| `--json` | the unexpired claim records as a JSON array (`[]` when none) |
| `--repo PATH` | only claims for that repository; the path is hashed the same way `brain-claim` hashes it |
| `--gc` | remove expired claims, emitting `work.claim.expired` per claim |

### The claim record

`$AGENTBRAIN_DIR/vault/claims/<host>-<agent>-<id>.json`

```json
{
  "id": "6f2a0c91d4b7",
  "agent": "session-a",
  "host": "workstation",
  "intent": "one command that runs every gate",
  "paths": ["scripts/run-gates.mjs", "package.json"],
  "repo": "3f9c0a1b2d4e5f60",
  "branch": "feat/some-work",
  "taken_at": "2026-09-22T08:14:02.119374Z",
  "expires_at": "2026-09-22T16:14:02.119374Z"
}
```

- `id`: 12 hex characters, random.
- `repo`: the first 16 hex characters of the SHA-256 of the repository path
  (`git rev-parse --show-toplevel`, else the physical working directory, `pwd -P`). The
  path itself is never stored, because the claims directory lives in the shared vault.
  Two worktrees of one project have different top-levels and therefore different `repo`
  values.
- `branch`: `git rev-parse --abbrev-ref HEAD`, empty outside git. Shown by `brain-claims`;
  not used for comparison.
- `paths`: exactly what was passed to `--paths`, split on commas; `[]` when omitted.

### Two stores

| | where | why |
|---|---|---|
| current state | `vault/claims/*.json` | a handful of files, read in milliseconds |
| history | the event log, via `brain-emit` | `work.claim.taken` / `work.claim.released` / `work.claim.expired`, outlives the sessions |

The claims directory is a **projection**, not a second bus: one file per claim answers
"what is held" by existing. Writing the claim file is required; emitting the history
event is best-effort and never fails the command. Best-effort is not silent: when
`brain-emit` is missing or fails (no `brain.json`, an unwritable inbox), the command
prints a `warning: ... not written to the event log` line on stderr and keeps its exit
code.

History events are sent with `brain-emit --broadcast`, because the log is for whoever
reads it later rather than for one recipient. `from` is the claiming agent (for
`work.claim.expired`, the agent that held the claim), and the payload is the claim
record as stored in `vault/claims/`.

## Expiry

Every claim carries `expires_at`. `brain-claims` does not list an expired claim. A session
that keeps working re-claims; a session that crashes disappears on its own. There is no
daemon and no heartbeat.

Resolution order, highest first:

1. `--ttl` on the claim
2. `claim_expiry_hours` in `vault/events/config.json`
3. the built-in default of **8 hours**

```json
{
  "claim_expiry_hours": 8
}
```

The file is optional; a missing file or a missing key means the built-in applies. Eight
hours covers a working day, so a claim taken at the start of a session still holds when
the work reaches its files.

`brain-claims` filters expired claims from its output and writes nothing, so anyone can
run it to look. Removing them is `brain-claims --gc`, the same split the addon makes
between `brain-poll` and `brain-events-gc`.

## Re-claiming

`brain-claim` with the same agent, intent and `repo` as an existing claim extends that
claim instead of writing a second one: `expires_at` is reset to now plus the resolved
expiry, the existing id is printed, and the command exits 0 without a collision check or
a new event. Expiry therefore measures time since the last claim, not since the first.

## Collisions

Checked before a new claim is written, against unexpired claims with the same `repo`:

| | behaviour | exit |
|---|---|---|
| a claimed path overlaps | a `path overlap` warning on stderr per held path; the claim is still recorded | **3** |
| nothing overlaps | only the id is printed | 0 |

Path overlap is prefix-based in both directions: claiming `scripts/` warns against a held
`scripts/run-gates.mjs`, and the other way round.

**Intent is not compared.** Two phrasings of one intention often share no word, so
`brain-claim` does not guess; run `brain-claims` to read what is held.

### Exit codes

| code | `brain-claim` | `brain-claims` |
|---|---|---|
| 0 | recorded, re-claimed or released | listed (also when nothing is held), or gc done |
| 1 | `--release` with an unknown id | |
| 2 | usage error, or `jq`/`python3` missing | usage error, or `jq`/`python3` missing |
| 3 | recorded, but a claimed path overlaps | |
| 7 | the claim could not be written | the current time could not be computed |

## Agent-agnostic

JSON files with atomic rename, exactly like the rest of the addon (see [[SPEC-storage]]).
A Pi agent, a shell script or any other agent writes the same files. `brain-claim` is
convenience; **the format is the contract**.

## Event types

| type | emitted by | status |
|---|---|---|
| `work.claim.taken` | `brain-claim` | IMPL |
| `work.claim.released` | `brain-claim --release` | IMPL |
| `work.claim.expired` | `brain-claims --gc` | IMPL |

All three follow the `<context>.<entity>.<action>` convention in [[SPEC]]. The payload is
the claim record.

## Identity is the session, not the person

`agent` resolves as `--agent`, else `BRAIN_AGENT`, else the Claude Code session id
(`CLAUDE_CODE_SESSION_ID`) shortened to `session-<first 8 characters>`, else `$USER`.
Colliding sessions typically run on one machine as the same user, so a claim naming the
user would tell them nothing.

Identity stays self-declared. The trust boundary is repository access, as
[[SPEC]] records under Trust model; signatures are backlog, and a claim only ever
produces a warning, never a block.

## Not in scope

No blocking, no `--force`, no takeover, no priority, no UI. Expiry already clears a
forgotten claim; being *shown* the other claim is enough.

## Testing

`tests/test-claims.sh` runs in a temporary `AGENTBRAIN_DIR` and pins:

- a claim with no overlap exits 0
- a claim on an overlapping path warns, exits 3 and is still recorded
- a claim on an unrelated path exits 0
- an expired claim is not listed, and listing does not delete it
- `--gc` removes the expired claim
- re-claiming with the same agent, intent and repo does not add a file
- `BRAIN_AGENT` becomes the `agent` field
- `claim_expiry_hours` in the config sets the expiry, and `--ttl` beats it
- `--release` removes the claim
- each new claim, each release and each `--gc` removal writes exactly one
  `work.claim.taken` / `work.claim.released` / `work.claim.expired` event to
  `vault/events/inbox/`, broadcast, with the claim record as payload; a re-claim writes
  none
- with a broken event log the claim still exits 0, is still recorded, and the lost event
  is reported on stderr
