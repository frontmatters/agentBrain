---
date: 2026-09-14
type: system
tags: [skill, browser-monitor, debugging, playwright]
id: 3b614800-5835-56d4-b866-13fe626a3029
---

# browser-monitor

Watch the owner work in a browser, record what breaks, leave a report.

## Why it exists

A scripted reproduction clicks what the author knew to click. A person clicks what
is there. Between those two sits every bug that survives testing: a blur at the
wrong moment, a switch flipped after typing, an id left over from the previous
screen. This skill was written on 2026-09-14 after three scripted runs passed while
the owner's own session kept losing data. The first monitored session found the
cause in ninety seconds.

## What it does

Opens a visible browser, navigates once, then listens only:

- failed API calls, with the server's answer verbatim
- JavaScript exceptions, with the stack
- the payload of saves you name, with the number of rows
- a request that leaves without a body, flagged separately: the shape most silent
  data loss arrives in
- the state of elements you name, logged when it changes

On stop it writes a markdown report beside the log: what was looked at, the
failures grouped, the last sixty lines of the timeline, and a section for what is
still unexplained.

## Files

| Path | What |
|---|---|
| `SKILL.md` | the procedure, the one rule, and how to read the log |
| `bin/monitor.py` | the watcher; `--watch TAG:path` and `--api-filter` do the work |

## Requires

Python with Playwright (`playwright` importable, Chromium installed). The script
launches a headed browser, so it needs a desktop session. It is not usable over a
plain ssh connection.

## Related

- `superpowers:systematic-debugging`: what to do with the evidence once you have it
- `peer-review`: for the fix that follows, when it ships
