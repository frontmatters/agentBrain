---
date: 2026-06-10
type: system
tags: [addon, event-bus, changelog]
id: 2ad546fa-b340-53b0-9cb5-2c4f1829667e
---

# Changelog

All notable changes to this addon are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this addon adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `brain-poll --summary` adds `broadcast` (true when the event was sent to
  everyone), so a listener can tell mail addressed to it from an announcement
  without opening the envelope.
- `brain-status <id|prefix>` reports one event's lifecycle from stored facts
  only: sent, read (from the recipient's own cursor; `unknown` when it keeps
  none), acked (`*.received` replies) and answered (`in_reply_to` or
  `causation_ids`). `--open <agent>` lists `*requested` events that agent has
  not answered. Metadata only, shape-checked like `--summary`; ambiguous
  prefixes exit 2.
- `brain-poll --commit-id=<id>` is the read receipt: it marks exactly one
  inspected event as seen, and refuses unknown ids, prefixes and events not
  routed to the caller.
- `brain-poll --wait=SEC --summary` adds bounded, non-committing, routed
  long polling (pre-existing events, new events and timeout covered by fixtures).
- `brain-poll --correlation-id` and `--in-reply-to` select exact threads and
  direct replies (empty filters fail closed); `--summary` returns only
  bounded routed metadata, replaces malformed fields with `<invalid>`, and
  cannot advance a cursor or expose payload/ref/host fields.
- Opt-in Pi `pi/bus-wake.ts` prototype for session-scoped, metadata-only
  mailbox notifications. Cloud-model auto-wake is blocked; local-model wake
  requires literal HTTP loopback and private opt-in. Mock-session tests cover
  role, shutdown, injection and provider gating; idle Pi wake is unverified.
- Document the interactive-agent handshake, honest ping semantics and the
  per-run cloud disclosure boundary for future automatic responders.
- `brain-name`: a unique, readable listener name (`calm-robin`) derived from the
  Claude Code session id or a given key, with a djb2-based adjective-animal generator.
  Two sessions listening as the same agent share a cursor and take each other's
  events; a per-session name ends that. `tests/test-name.sh` pins the output and,
  with `BRAIN_NAME_REFERENCE` set, fails when the word lists drift from a reference.

## [0.3.1] - 2026-07-26

### Added

- `CHANGELOG.md` itself, per the new agentBrain addon changelog convention
  (Keep a Changelog + SemVer, see `system/addons/README.md`).

## [0.3.0] - 2026-06-10

### Added

- Retroactively backfilled entry — this changelog was introduced after the
  addon already existed at this version. See `README.md` and this repo's
  git history (`git log -- system/addons/event-bus/`) for the actual change
  history prior to this file's creation.
