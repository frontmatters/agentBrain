---
date: 2026-05-25
type: spec
tags: [spec]
source: session
version: 0.3.0
id: ce6aa836-ec21-5149-afda-de665155a409
---

# event-bus SPEC-storage — filesystem, cursor, audit, retention

Storage-layer concerns of the event-bus: where events live on disk, how consumers
track what they've seen, how audit-records are kept, and how retention works.

For protocol (envelope, topics, threading, routing) see [[SPEC]]. For handshake
see [[SPEC-ping]].

**Status legend**: `IMPL` / `PARTIAL` / `DESIGN` / `BACKLOG`.

---

## 1. Directory layout (IMPL)

```
local/events/
├── inbox/                    # active events (IMPL — created on first emit)
│   └── <ts-safe>-<topic-slug>-<id8>.json
├── cursors/<host>/<agent>/   # per-consumer state (IMPL)
│   ├── seen-ids.set          # one event_id per line — canonical dedup
│   └── seen-ids.set.lock     # mkdir-mutex during --commit
├── audit/<host>/<agent>/     # per-writer audit log (PARTIAL)
│   └── <YYYY-MM-DD>.ndjson
├── archive/                  # BACKLOG — GC moves events here after retention
└── audit-archive/<host>/<agent>/  # BACKLOG — old audit records
```

> `BACKLOG`: `archive/` and `audit-archive/` directories — `brain-events-gc` script
> to move old events into them. v0.3 keeps everything in `inbox/` and `audit/`;
> retention is manual.

> `DESIGN`: `streams/<context>/<topic>/...` symlink index per topic. Not built;
> `find inbox/ -name "*-<topic>-*"` is the current alternative and works fine
> for <10k events.

---

## 2. Filename format (IMPL)

`<YYYYMMDDTHHMMSS>-<microseconds>Z-<topic-slug>-<id8>.json`

Example: `20260525T020930-555012Z-peer-review-review-completed-a4b3c2d1.json`

Properties:
- **NTFS-safe**: no `:` (git-bash on Windows would break)
- **Lexicographically sortable**: `ls | sort` = chronological order
- **Topic-slug**: dotted-type with dots → dashes (`peer-review.review.completed` → `peer-review-review-completed`)
- **id8**: first 8 chars of full `event_id` (informational; full id in envelope JSON)

---

## 3. Atomic-write protocol (IMPL)

```
1. Write to <final-name>.tmp in the same directory (same filesystem → atomic mv guarantee)
2. mv <final-name>.tmp <final-name>  (atomic on POSIX and NTFS)
3. Consumers MUST ignore *.tmp files during scan
4. .tmp files are gitignored — partial writes never get synced
```

No reader ever sees a half-written file. No `flock` needed. Cross-platform identical.

`brain-emit` enforces this with a cleanup-trap that removes orphan `.tmp` on
unexpected exit (so failed writes don't accumulate cruft).

---

## 4. Cross-platform primitive matrix

| Primitive | macOS | Linux | Windows (git-bash) | Decision |
|---|---|---|---|---|
| atomic-write + `mv` | ✓ | ✓ | ✓ | Required pattern |
| mtime resolution | µs | ns | s | Don't trust mtime; use filename timestamp |
| symlinks (streams/) | ✓ | ✓ | limited | Not used in v0.3 (DESIGN) |
| `jq` | brew | apt | bundled | Required dependency |
| `inotify`/`fsevents` | fsevents | inotify | limited | Not used — polling-only |
| file-locking | `lockf` | `flock` | varies | Not used — atomic-rename + mkdir-mutex (cursor) |

---

## 5. Cursor (IMPL)

Per consumer: `local/events/cursors/<hostname>/<agent>/`

```
cursors/<hostname>/<agent>/
├── seen-ids.set      # plain text, one event_id per line (IMPL)
└── seen-ids.set.lock # mkdir-based mutex during --commit (IMPL)
```

> `DESIGN`: `last-seen-filename.txt` and `lookback-window.txt` per-agent override
> files in spec v0.2. Not implemented — lookback comes from CLI flag (`--lookback=`)
> with sensible default. Add when a use-case appears.

### Polling algorithm (sync-safe)

```
brain-poll --agent=<name>:
  1. scan_window_start = now() - lookback (default 7d)
  2. files = sort(inbox/) | filter(filename_timestamp >= scan_window_start)
  3. for each file:
       parse event_id from envelope
       skip if event_id ∈ seen-ids.set
       skip if NOT matches_me (routing filter from SPEC §4)
       skip if NOT type-filter match
       yield envelope to consumer
  4. on --commit:
       acquire mkdir-mutex on seen-ids.set.lock
       append all yielded event_ids to seen-ids.set
       release mutex
```

**Key**: filtering uses `seen-ids.set` (canonical identity), NOT filename comparison.
This means events arriving via gitea-sync with older timestamps are still seen
correctly — as long as they're within the lookback window.

### Lookback window

| Use case | lookback |
|---|---|
| Local-only dev (real-time) | 1h |
| Multi-machine, daily sync (default) | 7d |
| Laptop "comes home" weekend | 14d |
| Long-offline machines | 30d (matches archive-retention) |

Too short = miss sync-late events. Too long = unnecessary I/O.

### At-least-once semantics

Cursor advances ONLY after explicit `--commit`. Without `--commit`, polling is
read-only inspection (events stay un-seen). Consumer-side must use `event_id`
idempotency for any side-effect-producing logic.

> `PARTIAL`: trim-seen-ids policy is documented but not implemented. seen-ids.set
> grows unbounded. At ~50 events/KB, this becomes a concern around 100k events
> (~2MB file, linear-scan dedup gets slow). BACKLOG: `brain-events-gc --trim-seen-ids`.

---

## 6. Audit log (PARTIAL)

Layout: `local/events/audit/<hostname>/<agent>/<YYYY-MM-DD>.ndjson`

One file per (host, agent, date) tuple → no two processes write to the same file
under normal use → merge-conflict-free under gitea-sync.

### Audit record schema (v0.3 actual)

```json
{
  "timestamp": "<ISO-8601 µs Z>",
  "action":    "emit",
  "event_id":  "<event_id>",
  "type":      "<topic>",
  "file":      "<filename>"
}
```

> `PARTIAL`: v0.3 only writes `action: "emit"` from brain-emit. The fuller spec
> below describes the intended end-state.

### Audit-record schema (DESIGN end-state)

```json
{
  "audit_id":        "<uuid4>",
  "audit_type":      "published | consumed | rejected | failed | cursor-advanced",
  "ts":              "<ISO-8601 µs Z>",
  "actor":           { "agent": "...", "host": "...", "instance_id": "..." },
  "target_event_id": "<event_id this record refers to>",
  "target_filename": "<file>.json",
  "target_type":     "<topic>",
  "reason":          "<for rejected/failed>",
  "parse_error":     "<for malformed input>",
  "details":         { ... }
}
```

| Type | When | Status |
|---|---|---|
| `published` | After successful brain-emit mv-atomic | PARTIAL (written as `action: "emit"`) |
| `consumed` | After brain-poll --commit | DESIGN — not written today |
| `rejected` | Schema validation failed | BACKLOG |
| `failed` | Consumer handler returned non-zero | DESIGN |
| `cursor-advanced` | Cursor moved forward | DESIGN — `consumed` covers this in practice |

### Why audit log next to events

| Concern | Events alone | Events + audit |
|---|---|---|
| Who published what? | Reconstructable from `from` field | Plus exact write-finished timestamp |
| Who consumed what? | **NOT** (cursor advance is local state) | Logged per consumer (when DESIGN ships) |
| Rejected/failed events | Invisible | Logged with reason |
| Forensics | Hard to reconstruct from cursor states | Direct timeline |

### Write semantics

> `PARTIAL`: v0.3 uses `echo "$entry" >> "$AUDIT_FILE"`. POSIX O_APPEND is atomic
> for writes ≤ PIPE_BUF (~4KB on most systems). Typical entries are 300-500B,
> so safe in practice. brain-emit emits a warning if entry > 4KB.
>
> `DESIGN`: full atomic-write via `.tmp + mv` for large entries — not implemented;
> would require buffering existing file + new line, write to tmp, atomic mv. Not
> worth the complexity for current entry sizes.

---

## 7. Gitignore policy (PARTIAL)

> `IMPL`: v0.3 has all of `local/` gitignored in both repos. Events therefore
> stay local; cross-machine sync requires a separate mechanism.
>
> `DESIGN`: spec-of-record was "events/inbox/, events/archive/, events/audit/
> ARE git-tracked → events propagate via gitea-sync." This requires:
> - `local/.gitignore` to opt-out specifically: `!events/inbox/`, `!events/audit/`
> - `events/cursors/**` MUST stay gitignored (machine-specific state)
> - `events/**/*.tmp` MUST stay gitignored (partial writes)
>
> Not enabled in v0.3 because cross-machine sync is deferred to v0.4+ (requires
> a home-server-as-backbone deployment + clock-skew handling).

---

## 8. Retention + GC (PARTIAL)

End-state design:

| What | Retention | After-retention action | Status |
|---|---|---|---|
| `inbox/*.json` | 30 days | Move to `archive/` | **implemented** (`brain-events-gc`) |
| `archive/*.json` | indefinitely (v0.3) | None | n/a |
| `audit/<host>/<agent>/*.ndjson` | 90 days | Move to `audit-archive/` | BACKLOG |
| `cursors/<host>/<agent>/seen-ids.set` | `2 × max(lookback)` | Trim entries beyond window | BACKLOG |

```bash
# Implemented: inbox→archive retention (dry-run by default; --apply to execute).
brain-events-gc [--retention=30d] [--apply]

# BACKLOG (not yet implemented): audit retention + seen-id trimming.
# brain-events-gc --audit-retention=90d --trim-seen-ids
```

Multi-machine GC safety would require a "seen-by-hosts" marker per event so GC
only proceeds after all known consumers have seen an event. Without this,
machines that come back online after long offline periods may re-process events
they actually saw on a different machine.

**v0.3 acceptable risk**: solo single-machine, manual cleanup if `inbox/` grows.
Defer GC implementation until cross-machine deployment lands.

---

## 9. Path safety

- Hostnames: `hostname -s` (short, no dots)
- Agent names: lowercase, kebab-case, no dots (consistent with topic-naming)
- `ref` field: vault-relative paths only (no absolute machine-specific paths)
- Archive filenames sanitized to alphanumeric + dash + underscore (no `/` or `..`)

---

## Related

- [[SPEC]] — protocol layer (envelope, topics, threading, routing)
- [[SPEC-ping]] — built-in smoketest
- [[README]] — script usage
