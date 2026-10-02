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

The `bin/` scripts also run directly from this path. `install.sh` verifies the
runtime deps (`jq`, `python3`, `openssl`), makes the bins executable, and symlinks
each of them into `~/.local/bin` (override with `EVENT_BUS_BIN_DIR`) so they are
callable by name from any directory:

```bash
bash scripts/addons.sh install event-bus      # privacy prompt + install.sh + enable
# or directly:
bash system/addons/event-bus/install.sh        # dep check + chmod + link into ~/.local/bin
```

Uninstall: the links in `~/.local/bin` are the only thing installed outside this
directory; `uninstall.sh` removes exactly those (a same-named binary that does not
point back here is left alone). Runtime state is the events in `vault/events/` (resolved through
`AGENTBRAIN_VAULT` when set), and only `--purge` deletes it:

```bash
bash system/addons/event-bus/uninstall.sh            # remove the ~/.local/bin links
bash system/addons/event-bus/uninstall.sh --purge    # also delete vault/events/ state
bash scripts/addons.sh disable event-bus             # disable the registry entry
```

## Quick start

### Emit an event

```bash
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-emit \
    --type=peer-review.review.requested \
    --to=pi \
    --from=claude \
    --payload='{"document":"system/addons/event-bus/SPEC.md","question":"is this design sound?"}'
```

Stdout = `event_id`. The event lands in `vault/events/inbox/<ts>-<topic>-<id8>.json`.

### Poll for events addressed to your agent

```bash
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-poll --agent=pi --commit
```

Outputs NDJSON (one envelope per line). `--commit` advances the cursor
(`vault/events/cursors/<host>/<agent>/seen-ids.set`) for **every yielded event**.
Drop `--commit` for dry-read and do not ACK an uninspected event.
`--correlation-id=<id>` filters a whole conversation; `--in-reply-to=<id>`
selects direct replies. Use `--summary` for metadata-only NDJSON (type,
agent name, IDs, time, broadcast flag): it never returns a payload, path, ref or hostname,
replaces malformed metadata with `<invalid>`, and refuses `--commit` and
`--raw`. Add `--wait=<seconds> --summary` (1–3600s) to rescan until a routed
match exists; exit 5 means timeout. Pre-existing messages match immediately,
and waiting never commits or ACKs. An agent still needs to treat metadata as
untrusted input; an armed harness adapter must handle the wait result to wake
a model.

### Test connectivity (ping/pong)

```bash
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-ping --agent=pi --timeout=10
```

Emits `system.bus.ping`, waits for matching `system.bus.pong`, verifies echo
token, prints RTT. Exit 0 = success, 1 = timeout, 2 = echo mismatch, 3 =
schema-invalid pong. A timeout means no *running listener* answered in time;
an interactive agent may still read the request on its next owner prompt.
`brain-chat --follow` shows an attributed read-only event timeline, but neither
it nor MCP tools wake an idle model. The opt-in interactive/always-on responder
design (not implemented) and its per-run cloud-consent boundary live in
[SPEC.md](SPEC.md#interactive-sessions-and-automatic-replies-design-not-shipped).

### Check what happened to a message

```bash
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-status 331538bb
$AGENTBRAIN_DIR/system/addons/event-bus/bin/brain-status --open claude
```

Shows sent, read, acked and answered for one event id (or an 8+ character
prefix), from what the bus already stores. "Read" means the recipient marked
it with `brain-poll --commit-id=<id>` after inspecting it; a recipient that
keeps no cursor shows `unknown`, never `no`. `--open` lists `*requested`
events an agent has not answered yet.

## The scripts

| Script | What | Spec ref |
|---|---|---|
| `brain-emit` | Publish event (envelope-validated, atomic-write, audit-logged) | `spec-envelope`, `spec-filesystem`, `spec-audit` |
| `brain-poll` | Read events matching `--agent` (with routing-filter + dedup) | `spec-cursor`, `spec-routing` |
| `brain-ping` | Smoketest — emit ping + wait for pong | `spec-ping` |
| `brain-name` | Listener name (`adjective-animal`) from a key, default the session id | none |
| `brain-chat` | One readable stream across every session | `SPEC-chat.md` |
| `brain-claim` | Record what this agent is about to work on, or release it | `SPEC-claims.md` |
| `brain-claims` | List who holds what; `--gc` removes expired claims | `SPEC-claims.md` |
| `brain-events-gc` | Move inbox events past retention into `archive/` (dry-run unless `--apply`) | `SPEC-storage.md` section 8 |

All eight take `--help` for full arg reference.

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

Full details split into five specs:
- [SPEC.md](SPEC.md) — protocol layer (envelope, topics, threading, routing)
- [SPEC-storage.md](SPEC-storage.md): filesystem, cursor, audit, retention
- [SPEC-ping.md](SPEC-ping.md): built-in smoketest handshake
- [SPEC-chat.md](SPEC-chat.md): `brain-chat`, the readable cross-session stream
- [SPEC-claims.md](SPEC-claims.md): `brain-claim` / `brain-claims`, who works on what

Each section uses `IMPL` / `PARTIAL` / `DESIGN` / `BACKLOG` markers so you can
tell at a glance what works today vs what is planned.

## Building a listener

`brain-poll` provides a durable routed mailbox, but calling it does not wake a
model. The ping-listener template is a smoketest only: it commits before
replying and must not be copied as a crash-safe worker.

### Pi mailbox adapter (opt-in prototype)

`pi/bus-wake.ts` uses this **same bus**, not a second mailbox. Pi loads an
extension at startup or `/reload`. To try it in a new Pi session:

```bash
pi --extension /path/to/agentBrain/system/addons/event-bus/pi/bus-wake.ts
```

It reads private `vault/addons/event-bus/config.json` from `AGENTBRAIN_DIR` or
the active `~/agentBrain` checkout. Missing config means `role: none` and does
nothing. To opt in, the owner can configure:

```json
{"session":{"role":"both","wake":"notify","interval_ms":5000,
            "allow_types":["agent.collaboration.requested"]}}
```

`role` can be `none`, `ask` (replies), `answer` (new requests), or `both`.
`allow_types` must list exact event types, without wildcards; an absent or
empty list disables the adapter even if `role` is set. A notification only
happens once per event per running session; reconnecting can notify again.
`notify` is **UI-only** and never starts a model turn. `local-model` can start
one Pi turn with `triggerTurn` only when the selected model URL is literal
HTTP loopback (`127.0.0.1` or `::1`). An owner-controlled LAN host is not
loopback. A local proxy may forward to cloud; verify the endpoint before
opting in. Cloud-model automatic replies are **not authorized** by this
config: per-run consent in `system/security-policy.md` still applies. The
adapter never opens a payload or ref, never commits a cursor or ACKs a
message, and stops its timer on session shutdown. `bun test
system/addons/event-bus/tests/bus-wake.test.ts` uses a fake Pi session and
sends nothing to a model; actual idle Pi wake is **not yet verified**.

## Cross-machine sync (deferred)

The spec proposes propagating events via git sync of `vault/events/`. Today
the addon itself never syncs: `vault/events/` is runtime state outside the
framework repo. If you sync your vault with git, add `events/cursors/` and
`events/inbox/` to the vault's `.gitignore`, or the event files travel with it.
Cross-machine cursoring + reconciliation requires `spec-cursor` + `spec-gc`
hardening; see backlog.

## Dependencies

- `bash` (POSIX 3.2+)
- `jq` (1.6+)
- `python3` (3.6+, for `uuid.uuid5` and ISO-8601 µs timestamps)
- `openssl` (for nonces)
- `hostname -s`
- `realpath` (built into macOS 13+ and GNU coreutils; lets the bins find their
  checkout when called through the `~/.local/bin` links)

## File layout (created on first emit)

```
vault/events/
├── inbox/                      # active events
│   └── <ts>-<topic-slug>-<id8>.json
├── archive/                    # brain-events-gc moves events here after retention
├── audit/<host>/<agent>/       # per-writer NDJSON audit log
│   └── YYYY-MM-DD.ndjson
└── cursors/<host>/<agent>/     # per-consumer state
    └── seen-ids.set
```

## Troubleshooting

- **`brain-emit: missing $AGENTBRAIN_DIR/brain.json` (exit 4).** The bus derives
  its root from the script path; set `AGENTBRAIN_DIR` to your brain checkout if you
  run the bins from elsewhere (e.g. via an alias), or run them from the checkout.
- **`invalid type` (exit 2).** Topics must be `<context>.<entity>.<action>`,
  lowercase kebab — e.g. `peer-review.review.requested`.
- **`invalid JSON in --payload` (exit 3).** `--payload` must be a single-quoted JSON
  object string: `--payload='{"k":"v"}'`.
- **Poll yields nothing.** Check routing: an event addressed `--to=pi` is only
  visible to `--agent=pi` (or a `--broadcast` event). Already-seen events are hidden
  unless you pass `--all`; the cursor lives in
  `vault/events/cursors/<host>/<agent>/seen-ids.set`.
- **A dependency is missing.** `install.sh` prints the install command for any
  missing `jq`/`python3`/`openssl` and exits non-zero rather than failing silently.
- **Run the tests.** `bash system/addons/event-bus/tests/test-event-bus.sh` exercises
  the emit→poll roundtrip, routing, cursor dedup, and validation against a tmpdir bus
  (no network, no real `vault/events/`).

## Validation

`scripts/checks/check-events.sh` validates every event in `vault/events/inbox/` and
`archive/` against the envelope schema, and `brain doctor` runs it. At read time,
`brain-poll` skips an invalid envelope with a stderr warning.
Only the bounded `--summary` form is suitable for a metadata-only notification.
Do not treat same-user event files or claimed sender names as authorization.
