---
name: browser-monitor
description: >-
  Watch the owner work in a browser and record what breaks. Use when a bug only
  appears in their hands and not in a scripted run, or when they ask you to watch
  ("kijk mee", "monitor mijn werk", "het werkt gewoon niet goed"). Opens a visible
  browser the owner drives, logs every failure with the server's answer, and writes
  a report another agent can pick up cold.
---

# browser-monitor: watch the owner work, record what breaks

The failure this fixes: a scripted reproduction passes and the owner's own session
still breaks. A script clicks what it knows; a person clicks what is there. Between
those two sits every bug that survives testing: a blur, a half-typed field, a tab
switch at the wrong moment, an id left over from a previous screen.

This skill opens a browser **the owner drives** and the agent only listens. It
records failed requests with the server's answer, JavaScript exceptions with their
stack, the payload of every save, and the state of whatever the owner is editing.
When it stops, it writes a report a different agent can pick up cold.

**Announce:** "Ik open een venster en kijk mee. Werk daarin, ik log wat er misgaat."

## The one rule

**Observe, never steer.** Navigate once at the start, then touch nothing. A cursor
that moves on its own while someone is demonstrating a bug destroys the evidence
and the trust. If the owner needs a different page, they open it.

## When to use

- The owner says a thing is broken that your own runs cannot reproduce.
- A bug depends on timing, focus, or a sequence nobody wrote down.
- The owner asks you to watch, monitor, or "kijk mee".

Do **not** use it to drive a flow yourself. That is a plain Playwright script. Do
not use it to record a demo. Do not leave it running unattended: it holds a browser.

## How

```bash
# start (background; the owner works in the window that opens)
python3 ~/agentBrain/system/skills/browser-monitor/bin/monitor.py \
  --url http://127.0.0.1:3000/admin/records \
  --log .tmp/browser-monitor/$(date +%Y%m%d-%H%M).log \
  --watch record-editor:value.list \
  --api-filter records,accounts,events &

# read while it runs
tail -20 .tmp/browser-monitor/*.log

# stop and write the report the next agent reads
python3 ~/agentBrain/system/skills/browser-monitor/bin/monitor.py --stop --log <same path>
```

`--watch <tag>:<path>` polls one element's state every few seconds and logs it only
when it changes, so the log tells you what the owner had on screen when it broke.
`--api-filter` marks saves you care about and logs their payload size; a request
that leaves without a body is flagged separately, because an empty body is the
shape most silent data loss arrives in.

## Where the log goes

Under the **project**, never in the shared brain: a session log carries the owner's
real data. Default `<cwd>/.tmp/browser-monitor/<timestamp>.log`, with the report
beside it as `<timestamp>.md`. For a client project under a sealed space, that keeps
it inside the repo where the rest of the client's material already lives.

The report is written for a reader who was not there: what was being done, the
failures grouped by kind with counts, the exact server answers, and the state at the
moment of each failure. End it with what is still unexplained. An agent picking
this up needs the open question more than the summary.

## What to do with what you see

Read the log **before** theorising. The order of lines is the evidence: a state
change, then an exception, then a request, in that order, says the exception came
between the edit and the save, and that is usually where the bug is. A request
logged as `LEEG` (no body) after a normal-looking edit means a value arrived
undefined, which in a web component almost always means a native event was mistaken
for a value-carrying one.

Never report a cause the log does not show. "I could not reproduce it" is a finding;
a guess dressed as a diagnosis is not.
