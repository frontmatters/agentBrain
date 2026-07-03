---
date: 2026-05-24
type: system
tags: [addon, event-bus, transport]
id: 65724ccf-b4db-5f87-8b23-48bf320cfbcd
---

# Event Bus

Filesystem-based pub/sub for agent collaboration. No daemon, no broker, no
network — just JSON files + atomic-rename + a sync-safe cursor.

## Install / uninstall

There is **no real install step** — the `bin/` scripts run directly from this
path. `install.sh` only verifies the runtime deps (`jq`, `python3`, `openssl`) and
makes the bins executable, so running it is optional but a good preflight:

```bash
bash scripts/addons.sh install event-bus      # privacy prompt + dep check + enable
# or directly:
bash system/addons/event-bus/install.sh        # dep check + chmod bins
```

Uninstall: nothing is installed outside this directory, so there is nothing to
remove. The only state is runtime events in `local/events/`:

```bash
bash system/addons/event-bus/uninstall.sh --purge   # delete local/events/ state
bash scripts/addons.sh disable event-bus            # disable the registry entry
```

## Quick start

### Emit an event

```bash
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-emit \
    --type=peer-review.review.requested \
    --to=pi \
    --from=claude \
    --payload='{"document":"local/skills/event-bus/SPEC.md","question":"is this design sound?"}'
```

Stdout = `event_id`. The event lands in `local/events/inbox/<ts>-<topic>-<id8>.json`.

### Poll for events addressed to your agent

```bash
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-poll --agent=pi --commit
```

Outputs NDJSON (one envelope per line). `--commit` advances the cursor
(`local/events/cursors/<host>/<agent>/seen-ids.set`). Drop `--commit` for
dry-read.

### Test connectivity (ping/pong)

```bash
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-ping --agent=pi --timeout=10
```

Emits `system.bus.ping`, waits for matching `system.bus.pong`, verifies echo
token, prints RTT. Exit 0 = success, 1 = timeout, 2 = echo mismatch, 3 =
schema-invalid pong.

## The three scripts

| Script | What | Spec ref |
|---|---|---|
| `brain-emit` | Publish event (envelope-validated, atomic-write, audit-logged) | `spec-envelope`, `spec-filesystem`, `spec-audit` |
| `brain-poll` | Read events matching `--agent` (with routing-filter + dedup) | `spec-cursor`, `spec-routing` |
| `brain-ping` | Smoketest — emit ping + wait for pong | `spec-ping` |

All three take `--help` for full arg reference.

## Envelope schema (v1)

```json
{
  "event_id": "<uuid5>",
  "type": "<context>.<entity>.<action>",
  "envelope_schema_version": 1,
  "payload_schema_version": 1,
  "from": { "agent": "...", "host": "...", "instance_id": "..." },
  "to":   { "agents": [], "hosts": [], "broadcast": false },
  "timestamp": "<ISO-8601 µs Z>",
  "correlation_id": "<event_id of thread initiator>",
  "in_reply_to": "<event_id>",        // optional
  "causation_ids": ["<id>", ...],     // optional
  "reply_to": { "agent": "...", "host": "..." },  // optional
  "ref": "<vault-relative-path>",     // optional
  "payload": { ... }
}
```

Full details split into three specs:
- [SPEC.md](SPEC.md) — protocol layer (envelope, topics, threading, routing)
- [SPEC-storage.md](SPEC-storage.md) — filesystem, cursor, audit, retention
- [SPEC-ping.md](SPEC-ping.md) — built-in smoketest handshake

Each section uses `IMPL` / `PARTIAL` / `DESIGN` / `BACKLOG` markers so you can
tell at a glance what works today vs what is planned.

## Building a listener

To make your agent respond to events, write a loop that calls `brain-poll` and
acts on matches. See `templates/ping-listener.template.sh` for a minimal
ping/pong responder.

## Cross-machine sync (v1.5 deferred)

The spec proposes propagating events via gitea-sync of `local/events/`. For v1
the addon runs **local-only** — `local/events/` is gitignored as runtime state.
Cross-machine cursoring + reconciliation requires `spec-cursor` + `spec-gc`
hardening; see backlog.

## Dependencies

- `bash` (POSIX 3.2+)
- `jq` (1.6+)
- `python3` (3.6+, for `uuid.uuid5` and ISO-8601 µs timestamps)
- `openssl` (for nonces)
- `hostname -s`

## File layout (created on first emit)

```
local/events/
├── inbox/                      # active events
│   └── <ts>-<topic-slug>-<id8>.json
├── archive/                    # GC moves events here after retention (v1.5)
├── audit/<host>/<agent>/       # per-writer NDJSON audit log
│   └── YYYY-MM-DD.ndjson
└── cursors/<host>/<agent>/     # per-consumer state
    ├── seen-ids.set
    └── last-seen-filename.txt  # informational only
```

## Troubleshooting

- **`brain-emit: missing $AGENTBRAIN_DIR/brain.json` (exit 4).** The bus derives
  its root from the script path; set `AGENTBRAIN_DIR` to your brain checkout if you
  run the bins from elsewhere (e.g. via an alias), or run them from the vault.
- **`invalid type` (exit 2).** Topics must be `<context>.<entity>.<action>`,
  lowercase kebab — e.g. `peer-review.review.requested`.
- **`invalid JSON in --payload` (exit 3).** `--payload` must be a single-quoted JSON
  object string: `--payload='{"k":"v"}'`.
- **Poll yields nothing.** Check routing: an event addressed `--to=pi` is only
  visible to `--agent=pi` (or a `--broadcast` event). Already-seen events are hidden
  unless you pass `--all`; the cursor lives in
  `local/events/cursors/<host>/<agent>/seen-ids.set`.
- **A dependency is missing.** `install.sh` prints the install command for any
  missing `jq`/`python3`/`openssl` and exits non-zero rather than failing silently.
- **Run the tests.** `bash system/addons/event-bus/tests/test-event-bus.sh` exercises
  the emit→poll roundtrip, routing, cursor dedup, and validation against a tmpdir bus
  (no network, no real `local/events/`).

## Validation

Doctor extension `check-events.sh` is on the v1.5 backlog. For now: invalid
envelopes are skipped by `brain-poll` with a stderr warning. Run `jq` over any
suspect file to sanity-check.
