---
name: peer-review
description: "Async cross-agent review of any document via the agentBrain event-bus. Emits peer-review.review.requested; any consumer agent (running as listener with any LLM backend) emits peer-review.review.completed. Caller can return immediately and poll later, or --wait for the first verdict. Default backend ollama-cloud:gpt-oss:20b-cloud. Triggers: 'peer-review', 'let X review', 'second opinion', 'external review', 'have another model check this'."
---

# peer-review (v2)

Async cross-agent review skill. Wraps the [[event-bus]] addon: emit a
`peer-review.review.requested` event, any consumer agent picks it up, runs
their LLM, and emits `peer-review.review.completed` back. No blocking call,
no per-agent CLI registry — just events.

## Location

```
~/agentBrain/system/skills/peer-review/
```

## Quickstart

```bash
# Fire-and-forget: emit request, return event_id, caller polls later
bash bin/peer-review path/to/SPEC.md --to=any

# Synchronous-style: wait for first completed (default 120s)
bash bin/peer-review path/to/SPEC.md --to=any --wait

# Wait + auto-archive the verdict
bash bin/peer-review path/to/SPEC.md --to=any --wait=60 --archive

# Consume mode: become a reviewer (runs as a listener)
bash bin/peer-review --consume --as=test-reviewer --llm=ollama-cloud:gpt-oss:20b-cloud

# Inspect events in a thread
bash bin/peer-review --list --correlation=<event_id> --from=claude

# Archive a completed event you previously received
bash bin/peer-review --archive <completed_event_id> --from=claude
```

## Architecture

```
caller agent                      bus                       consumer agent
    │                              │                              │
    │── peer-review <doc> ────────►│                              │
    │   --to=any --wait            │                              │
    │                              │── peer-review.review.requested
    │                              │                              │
    │                              │                              │ (poll)
    │                              │◄──────────────────────────── │
    │                              │                              │ (LLM call)
    │                              │── peer-review.review.completed
    │                              │                              │
    │◄──── completed event ────────│                              │
    │   (verdict + body)           │                              │
```

## Modes

| Mode | Flag | Purpose |
|---|---|---|
| **request** (default) | positional `<doc>` | emit `peer-review.review.requested` |
| **consume** | `--consume --as=<agent>` | listener: poll requests, call LLM, emit completed |
| **list** | `--list` | inspect events in a thread |
| **archive** | `--archive <event_id>` | render a completed event to `local/reviews/` |

## LLM backends (consume mode)

| Spec | Notes |
|---|---|
| `ollama-cloud:gpt-oss:20b-cloud` | default — fast, free, no rate-limit |
| `ollama-cloud:gpt-oss:120b-cloud` | deeper review, ~50s, found HIGHs that 20b missed |
| `ollama:<local-model>` | local Ollama (private, slow without GPU) |
| `gemini` | gemini CLI (rate-limited as of 2026-05) |
| `echo` | fixed stub for pipeline-testing |

## v1 → v2 changes

- **Dropped**: per-agent CLI registry (agents.sh), per-agent invoke functions, heartbeat/watchdog complexity, --dry-run, --no-log
- **Replaced**: blocking-call to pi/codex/gemini → emit + (optional) wait via event-bus
- **Added**: --consume mode (listener), --list, --archive as standalone post-receipt
- **v1 binary** preserved as `bin/peer-review-v1-deprecated.sh` for reference

## Why v2

v1.4.2 was synchronous: invoked `pi -p`/`codex`/etc. headlessly with
heartbeat+timeout watchdog. Real-world: pi-CLI blocked structurally under
lock-conflict with concurrent interactive sessions (15+ min silent hangs).
v2 makes the workflow async by construction: caller emits + returns
immediately, consumer agent processes at its own pace.

See [[forward:pi-cli-non-interactive-blocking-workarounds]] for the
underlying-problem context that led to this rewrite.

## When to use

- SPEC, design or plan ready — want an independent review without echo-chamber risk
- Convergence-evidence via multiple reviewers (different LLMs)
- Cross-machine: requester on laptop, consumer on desktop (via gitea-sync v1.5)

## Post-review re-evaluation — MANDATORY

**Peer-review is not infallible.** Reviewers miss context, hallucinate facts,
or push on things that are no issue in practice. Blindly adopting LLM feedback
is an anti-pattern (performative agreement → false positives in production).

**Empirical evidence**: on 2026-06-02 a gpt-oss:120b review found a "HIGH severity"
issue claiming that `uuid5-gen.sh` expects an absolute path. Verification (1 minute bash-run
+ source-read) confirmed that the script actually accepts vault-relative paths.
False positive. Had the feedback been adopted blindly → unnecessary refactor.

### The protocol (5 steps)

After each `--wait`/`--archive` cycle, before any action on the feedback:

1. **Read the review, ending with an explicit classification per finding**:
   - `✅ AGREE` — finding is correct, apply the fix
   - `❌ FALSE POSITIVE` — reviewer was wrong; verify and document why
   - `⚠️ DEFER` — valid but lower priority than the reviewer indicated
   - `❌ DISAGREE` — design choice or deliberate trade-off; document the reason
   - `🔄 NUANCE` — valid but the reviewer misses context; reformulation needed

2. **Verify each claim independently** before you classify it:
   - Reviewer claims a function does X? → read the source / run the command
   - Reviewer claims a section is missing something? → re-read the document yourself
   - Reviewer claims an approach is wrong? → check against project conventions
   - "It sounds logical" is not enough — proof required

3. **With multiple reviewers**: build a cross-validation matrix:
   - **Convergent findings** (2+ reviewers, the same issue) → strong signal, prioritize
   - **Single-model findings** → weaker signal, verify extra strictly
   - **Divergent verdicts** (one NEEDS-REVISION, another READY) → investigate why

4. **Decide priority based on your own verification**:
   - Not on reviewer-severity. The reviewer does not know your context.
   - P0 = actual blocker
   - P1 = convergent + confirmed yourself
   - P2/P3 = single finding after verification + impact assessment

5. **Document the re-evaluation** in handover/log/decisions:
   - Tally of AGREE / FALSE POSITIVE / DEFER / DISAGREE
   - Per FALSE POSITIVE: proof of why the reviewer was wrong
   - Per DISAGREE: reason (back-compat, breaking change, design intent)

### Anti-patterns

| Anti-pattern | Why bad |
|---|---|
| Adopting everything without verification | False positives end up in code/spec |
| "120b model = authority" | Larger models hallucinate too |
| Following severity blindly | A reviewer may rate a MEDIUM higher than your context requires |
| Skipping verification for "obviously right" findings | Confirmation bias |
| Performative agreement (confirming everything) | Reduces review value to 0 |

### When is re-evaluation "done"

- Every finding has a classification + rationale
- Every FALSE POSITIVE has proof
- The priority list (P0/P1/P2/P3) reflects your own judgment, not the reviewer's style
- For cross-review: the convergence matrix is made explicit

**Only then** may implementation of fixes start.

## When not to use

- Code-execution validation (use doctor.sh or tests)
- 1-line fixes (overkill)
- Immediate feedback needed (use `ollama run` directly or inline review)

## Heartbeat during --wait

During a blocking `--wait` the script prints a heartbeat to **stderr** every 15s so callers (human or CI) can see the poll-loop is still alive:

```text
peer-review: still waiting on 6a02f3cd-… (30s elapsed, 90s remaining)
```

Stdout stays clean for downstream `jq`/`tail` pipes. Adjust the cadence:
- Per-call: `--heartbeat=30` (or `--heartbeat=0` to turn it off)
- Default: env `PEER_REVIEW_HEARTBEAT=10`
- Non-numeric input → warning + fallback to 15s

## Caller-pattern: tee-tee instead of plain pipe

`peer-review … | tail -N` blocks on EOF when `peer-review` itself hangs: `tail` waits for an upstream-close that never comes. Use tee for live observability:

```bash
bash bin/peer-review path/to/SPEC.md --to=any --wait \
  | tee /tmp/review.out
# Inspect during the call:
tail -f /tmp/review.out
# After completion:
tail -20 /tmp/review.out
```

## Limitations / open items

- `--llm=gemini` is rate-limited — fallback to ollama-cloud
- Codex via pi is structurally unreliable (see [[forward:pi-cli-non-interactive-blocking-workarounds]])
- No multi-reviewer aggregator yet (--wait picks the first completed; for convergence run --list afterwards)
- No retry-policy on failed reviews (consume emits verdict=FAILED, caller responsible for the retry)

## Related

- [[event-bus]] — underlying transport
- [[peer-review-v1-deprecated]] — preserved old impl
- `local/reviews/` — archived verdicts
