---
date: 2026-05-22
type: system
tags: [addon, learnings, automation]
id: d3e5edcb-f53c-5f63-863d-1b13953d6fb5
---

# Extract Learnings (behavior add-on)

Auto-extracts durable, reusable learnings from a session transcript **before
compaction**, writing them into `local/learnings/extracted/`. It runs as a Claude
`PreCompact` hook and as a Pi `session_before_compact` extension.

- **Type**: behavior (patches `~/.claude/settings.json`; Pi extension wired by `configure-pi.sh`)
- **Privacy**: `sends-docs` — the session transcript text is sent to the configured
  summary model to extract learnings. Nothing else leaves the machine.
- **Requires**: `bun` (runs `core.ts`), `python3` (the hook parses its stdin payload).

## What is a "durable learning"?

A learning is a single, reusable, actionable sentence worth keeping beyond this
session — a fix, a gotcha, a convention, a non-obvious cause→effect. The model is
told to extract **0–5** of them and to **skip** trivial or one-off details. If the
session has nothing durable, nothing is written.

## Example output

Each learning becomes one file in `local/learnings/extracted/`, named
`<date>-<contenthash>.md` (the hash dedupes identical learnings):

```markdown
---
date: 2026-06-10
type: learning
tags: [extracted, session]
confidence: low
source: session
---

# Always pin global npm packages in CI; `latest` runs install hooks unreviewed.
```

`confidence: low` because these are machine-extracted — promote/curate as needed.

## Install

```bash
bash scripts/addons.sh install extract-learnings
# or directly:
bash system/addons/extract-learnings/install.sh
```

This registers a `PreCompact` hook in `~/.claude/settings.json` pointing at
`claude-precompact-hook.sh` (via the active-brain alias when present, so
`brain use dev|live` flips it). The Pi adapter is the existing
`session_before_compact` extension, wired by `configure-pi.sh` — nothing extra here.

## Uninstall

```bash
bash system/addons/extract-learnings/uninstall.sh           # remove the hook, keep learnings
bash system/addons/extract-learnings/uninstall.sh --purge   # also delete local/learnings/extracted
```

Uninstall is the true inverse of install: it removes only the entry whose command
contains `extract-learnings/claude-precompact-hook.sh` from `settings.json`, using
the same python patching. It is idempotent — running it with no hook installed is a
no-op.

## How it works

1. On `PreCompact`, Claude pipes `{transcript_path, ...}` to the hook on stdin.
2. The hook resolves the transcript path and, if `bun` is present, runs `core.ts`
   in the background (so compaction is never delayed).
3. `core.ts` flattens the transcript, asks the configured model for `LEARNING:`
   lines (bounded by a 60s timeout), and writes deduped files into
   `local/learnings/extracted/`.

The summary model is read from the youtube-digest summarizer config
(`local/addons/youtube-digest/channels.json` → `settings`) when present, else it
falls back to Pi's active model. No provider is hard-coded.

## Troubleshooting

- **Nothing is extracted / no files appear.**
  - `bun` not on PATH: the hook prints `extract-learnings: 'bun' not found on PATH`
    to stderr and exits 0 (it never blocks compaction). Install bun: https://bun.sh.
  - Session too short: transcripts under ~50 words are skipped by design.
  - No durable learnings: the model legitimately returned nothing.
- **The hook never fires.** Confirm it is registered:
  `python3 -c "import json;print(json.load(open(__import__('os').path.expanduser('~/.claude/settings.json')))['hooks'].get('PreCompact'))"`.
  Re-run `install.sh` if the entry is missing. Hooks only fire on compaction, so
  trigger one (or wait for auto-compaction) to see output.
- **Model hangs.** The call is bounded by a 60s timeout; on timeout it writes 0
  learnings rather than stalling.

## Tests

`bun test tests/core.test.ts` (wired via the manifest `test:` field). The suite
mocks the model call, so it runs offline and writes to a tmpdir — it never touches
the real `local/learnings/extracted/` or the network.

## Backend & privacy

The extractor sends the (flattened) session transcript to an LLM. Which one:

1. the summarizer configured in `local/addons/youtube-digest/channels.json`
   (`settings.summarizer`), when present;
2. otherwise **Pi's active model — i.e. whatever provider your agent happens
   to be running on** (Anthropic, Google, a local Ollama, ...).

That fallback is convenient but opaque: transcripts can contain anything you
typed or pasted in a session. If you want a guaranteed-local path, configure
an explicit local summarizer (e.g. `ollama`) in that settings block. To stop
extraction entirely: `bash scripts/addons.sh disable extract-learnings`.

