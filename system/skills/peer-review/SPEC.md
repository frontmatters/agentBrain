---
date: 2026-05-24
type: spec
tags: [spec]
version: 2.0.3
id: 87d61620-3ad8-5434-8f26-a0affd9d88e2
---

# peer-review: async cross-agent document review

**Version**: 2.0.3 (matches `bin/peer-review --help`)
**Implementation**: bash, `bin/peer-review`; requires `jq` and the [[event-bus]] addon
**Skill location**: `$AGENTBRAIN_DIR/system/skills/peer-review/`
**`$AGENTBRAIN_DIR`**: env-overridable, defaults to `realpath ~/agentBrain`

`bin/peer-review --help` is the reference for flags; this spec describes the
behaviour behind them.

## 1. Purpose

A document written by one agent benefits from review by another model with
different blind spots. `peer-review` turns that into an asynchronous exchange
over the event-bus: a requester emits a review request, any consumer agent
answers it with its own LLM backend, and the requester reads, waits for or
archives the answer.

## 2. Events

| Type | Emitted by | Key payload fields |
|---|---|---|
| `peer-review.review.requested` | request mode | `document` (vault-relative path when inside `$AGENTBRAIN_DIR`, else absolute), `document_sha256`, `document_lines`, `document_bytes`, `focus`, `requester`, `content` (full document text) |
| `peer-review.review.completed` | consume mode | `verdict`, `summary`, `body` (review text), `document`, `reviewer: {agent, llm}` |

A completed event carries `in_reply_to` and `correlation_id` set to the request's
`event_id`, and `ref` set to the document path. A failed review is also a
`completed` event, with `verdict: "FAILED"` and the reason in `summary`, so a
waiting caller always receives an answer.

## 3. Modes

### 3.1 request (default): `peer-review <doc>`

1. Reject a missing `<doc>` (exit 1) or a non-existent file (exit 4).
2. Build the payload. Documents over 100 KB trigger a stderr warning, because the
   payload travels as one command-line argument and can exceed `ARG_MAX`.
3. Emit `peer-review.review.requested` as `--from` (default `$BRAIN_AGENT`, else
   `claude`). `--to=any` or no target broadcasts; `--to=<agent>` targets one
   consumer. `--agent` is an alias for `--to`.
4. Print the new `event_id` on stdout. An empty id from `brain-emit` is exit 4.
5. Without `--wait`, return immediately.

With `--wait[=sec]` (default 120 s):

- If no consumer runs, start one in the background (`--as=<from>-autostart`,
  same `--llm`) and stop it when the call returns, including on timeout or
  signal. `--no-autostart-consumer` disables this.
- Poll every 2 s for a `completed` event whose `in_reply_to` matches, and print
  it as JSON on stdout.
- Print a heartbeat on stderr every `--heartbeat` seconds (default 15, env
  `PEER_REVIEW_HEARTBEAT`, 0 disables; a non-numeric value warns and falls back
  to 15). Stdout stays clean for `jq`.
- With `--archive`, archive the received event (section 3.4).
- Exit 0 on a review, 3 on `verdict: "FAILED"`, 2 on timeout.

### 3.2 consume: `peer-review --consume --as=<agent>`

A listener loop. Every 5 s it polls requests addressed to `<agent>` (or
broadcast) within `--lookback` (default 1h), marks them seen, and handles each:

1. Build the review prompt from `document`, `focus` and `content` (section 4).
2. Call the LLM backend (section 5).
3. Emit `completed` back to the requester. If the LLM call fails, or the
   completed emit itself fails, emit a `FAILED` completion instead.

A failure on one request is logged and the loop continues. `--once` exits after
one poll cycle.

### 3.3 list: `peer-review --list`

Print peer-review events visible to `--from` as one JSON line each
(`event_id, type, from, in_reply_to, correlation_id, ts`). Filters:
`--type=requested|completed|all` (default all), `--correlation=<id>` (passed to
`jq` with `--arg`, never interpolated), `--lookback` (default 7d). An empty bus
is a valid empty result, not an error.

### 3.4 archive: `peer-review --archive <event_id>`

Render a completed event (searched within 30 days) to
`vault/reviews/<utc-ts>-<doc>-by-<reviewer>.md`, or to `--out=<path>`.

- Frontmatter: `date`, `type: review`, `id` (UUID5 via `scripts/uuid5-gen.sh`,
  falling back to a random UUID), `doc-path`, `reviewer`, `llm`, `event_id`,
  `verdict`, `timestamp`. Values are stripped of newlines and quote-escaped so
  a review cannot inject frontmatter keys.
- The reviewer name in the filename is limited to `[A-Za-z0-9_-]`, which blocks
  path traversal.
- Body: `# Review of <doc> by <reviewer> (via <llm>)`, the summary, then the
  review text unchanged.

Prints the archive path on stdout. Unknown event: exit 4.

### 3.5 show-bus-path: `peer-review --show-bus-path <event_id>`

Print the absolute path of the event file in `vault/events/inbox/` or
`vault/events/archive/` on one line, for handing a request to another agent.
Not found: exit 4.

## 4. Review prompt

The consumer asks for a fixed output shape:

```
VERDICT: APPROVE | NEEDS-MINOR-REVISION | NEEDS-REVISION | REJECT
[SEVERITY] location | problem | fix      (at most 8 findings)
SUMMARY: <at most 2 sentences>
```

At most 400 words, no preamble. `focus` defaults to "correctness, completeness,
clarity, edge cases".

## 5. LLM backends

| `--llm` spec | Invocation |
|---|---|
| `ollama:<model>` | `ollama run <model>`; remote hosts via `OLLAMA_HOST` |
| `ollama-cloud:<model>` | `ollama run <model>` against a cloud model; the document leaves the machine |
| `gemini` | `gemini -p <prompt>` |
| `echo` | fixed stub reply, for tests |

Ollama output is cleaned of ANSI escapes, spinners, thinking blocks and timing
footers. An unknown spec fails per request (a `FAILED` completion), not at start.

Resolution when `--llm` is absent follows the cascaded config
(`system/security-policy.md`):

1. `PEER_REVIEW_DEFAULT_LLM`
2. `vault/config/llm.json` (`endpoint` + `model`), mapped to `ollama:<model>`;
   a non-local endpoint sets `OLLAMA_HOST`
3. the first local model in `ollama list`

Models ending in `:cloud` are never selected automatically. With nothing
resolved, consume mode refuses with setup instructions (exit 4). A backend
whose spec contains `:cloud` gets a data-exit notice when the consumer starts.

## 6. Configuration

| Env | Purpose |
|---|---|
| `AGENTBRAIN_DIR` | brain checkout root |
| `BRAIN_AGENT` | default `--from` |
| `PEER_REVIEW_DEFAULT_TO` | default `--to` |
| `PEER_REVIEW_DEFAULT_LLM` | default `--llm` for consume mode |
| `PEER_REVIEW_HEARTBEAT` | default heartbeat cadence in seconds |

## 7. Exit codes

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | invalid argument |
| 2 | no completed event before the `--wait` timeout |
| 3 | reviewer reported `FAILED` |
| 4 | filesystem or dependency error (event-bus missing, file not found, no backend, unknown event) |

## 8. Tests

- `test.sh`: all modes against the `echo` backend in a throwaway
  `AGENTBRAIN_DIR` sandbox; no network, no real vault writes.
- `tests/test-functions-defined.sh`: static check that every internal function
  call in `bin/peer-review` resolves to a definition.

## 9. Limitations

- The reviewer sees only the document, not the requester's session; see
  [[peer-review-out-of-band-limitation]].
- `--wait` returns the first completed review. For several reviewers, use
  `--list --correlation=<event_id>` afterwards.
- No automatic retry: a `FAILED` completion leaves the retry to the caller.
- Documents over roughly 100 KB can exceed the command-line argument limit.
- Adding a backend means extending `call_llm`; verify the exact invocation
  first, see [[cli-help-grep-not-equals-smoke-test]].
