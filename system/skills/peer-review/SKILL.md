---
name: peer-review
description: "Async cross-agent review of any document via the agentBrain event-bus. Emits peer-review.review.requested; any consumer agent (running as listener with any LLM backend) emits peer-review.review.completed. Caller can return immediately and poll later, or --wait for the first verdict. Default backend ollama-cloud:gpt-oss:20b-cloud. Triggers: 'peer-review', 'let X review', 'second opinion', 'external review', 'have another model check this'."
---

# peer-review (v2)

Async cross-agent review skill. Wraps the [[event-bus]] addon: emit a
`peer-review.review.requested` event, any consumer agent picks it up, runs
their LLM, and emits `peer-review.review.completed` back. No blocking call,
no per-agent CLI registry — just events.

## Locatie

```
~/agentBrain/system/skills/peer-review/
```

## Quickstart

```bash
# Fire-and-forget: emit request, return event_id, caller polls later
bash bin/peer-review path/to/SPEC.md --to=any

# Synchroon-style: wait for first completed (default 120s)
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
| `ollama-cloud:gpt-oss:120b-cloud` | deeper review, ~50s, vond HIGHs die 20b miste |
| `ollama:<local-model>` | local Ollama (private, slow without GPU) |
| `gemini` | gemini CLI (rate-limited as of 2026-05) |
| `echo` | fixed stub voor pipeline-testing |

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

## Wanneer gebruiken

- SPEC, design of plan klaar — wil onafhankelijke review zonder echo-chamber risk
- Convergence-evidence via meerdere reviewers (verschillende LLMs)
- Cross-machine: requester op laptop, consumer op desktop (via gitea-sync v1.5)

## Post-review herevaluatie — VERPLICHT

**Peer-review is niet onfeilbaar.** Reviewers missen context, hallucineren feiten,
of duwen op zaken die in praktijk geen issue zijn. Blind overnemen van LLM-feedback
is een anti-pattern (performatieve agreement → false positives in productie).

**Empirisch bewijs**: 2026-06-02 vond een gpt-oss:120b review een "HIGH severity"
issue dat `uuid5-gen.sh` een absoluut pad verwacht. Verificatie (1 minuut bash-run
+ source-read) bevestigde dat het script juist vault-relative paths accepteert.
False positive. Als de feedback blind was overgenomen → onnodige refactor.

### Het protocol (5 stappen)

Na elke `--wait`/`--archive` cyclus, vóór enige actie op de feedback:

1. **Lees de review eindigend met expliciete classificatie per finding**:
   - `✅ EENS` — finding klopt, fix toepassen
   - `❌ FALSE POSITIVE` — reviewer had fout; verifieer en documenteer waarom
   - `⚠️ DEFER` — terecht maar lager prioriteit dan reviewer aangaf
   - `❌ ONEENS` — design-keuze of bewust trade-off; documenteer reden
   - `🔄 NUANCE` — terecht maar reviewer mist context; herformulering nodig

2. **Verifieer elke claim zelfstandig** voordat je 'm classificeert:
   - Beweert reviewer dat een functie X doet? → lees de source / run de command
   - Beweert reviewer dat een sectie iets mist? → re-lees het document zelf
   - Beweert reviewer dat een aanpak fout is? → check tegen project-conventies
   - "Het klinkt logisch" is niet voldoende — bewijs vereist

3. **Bij meerdere reviewers**: bouw cross-validation matrix:
   - **Convergent findings** (2+ reviewers, dezelfde issue) → sterk signal, prioriteer
   - **Single-model findings** → zwakker signal, verifieer extra strikt
   - **Divergente verdicts** (een NEEDS-REVISION, ander READY) → onderzoek waarom

4. **Beslis prioriteit op basis van eigen verificatie**:
   - Niet op reviewer-severity. Reviewer kent jouw context niet.
   - P0 = werkelijke blocker
   - P1 = convergent + zelf bevestigd
   - P2/P3 = enkele finding na verificatie + impact-inschatting

5. **Documenteer de herevaluatie** in handover/log/decisions:
   - Tally van EENS / FALSE POSITIVE / DEFER / ONEENS
   - Per FALSE POSITIVE: bewijs van waarom reviewer het mis had
   - Per ONEENS: reden (back-compat, breaking change, design intent)

### Anti-patterns

| Anti-pattern | Waarom slecht |
|---|---|
| Alles overnemen zonder verificatie | False positives belanden in code/spec |
| "120b model = autoriteit" | Grotere modellen hallucineren ook |
| Severity-blind volgen | Reviewer kan een MEDIUM hoger inschatten dan jouw context vereist |
| Skip verification voor "obviously right" findings | Confirmation bias |
| Performatieve agreement (alles bevestigend) | Vermindert review-waarde tot 0 |

### Wanneer is herevaluatie "klaar"

- Elke finding heeft een classificatie + rationale
- Elke FALSE POSITIVE heeft bewijs
- De prioriteit-lijst (P0/P1/P2/P3) reflecteert eigen oordeel, niet reviewer-stijl
- Bij cross-review: convergence-matrix expliciet gemaakt

**Pas dan** mag implementatie van fixes starten.

## Niet gebruiken

- Code-execution validation (gebruik doctor.sh of tests)
- 1-line fixes (overkill)
- Onmiddelijke feedback nodig (gebruik direct `ollama run` of inline review)

## Heartbeat tijdens --wait

Tijdens een blocking `--wait` print het script elke 15s een heartbeat naar **stderr** zodat callers (mens of CI) zien dat de poll-loop nog leeft:

```text
peer-review: still waiting on 6a02f3cd-… (30s elapsed, 90s remaining)
```

Stdout blijft schoon voor downstream `jq`/`tail` pipes. Cadens aanpassen:
- Per-call: `--heartbeat=30` (of `--heartbeat=0` om uit te zetten)
- Default: env `PEER_REVIEW_HEARTBEAT=10`
- Niet-numeriek input → warning + fallback naar 15s

## Caller-pattern: tee-tee instead of plain pipe

`peer-review … | tail -N` blokkeert op EOF wanneer `peer-review` zelf hangt: `tail` wacht op upstream-close die niet komt. Gebruik tee voor live observability:

```bash
bash bin/peer-review path/to/SPEC.md --to=any --wait \
  | tee /tmp/review.out
# Inspect during the call:
tail -f /tmp/review.out
# After completion:
tail -20 /tmp/review.out
```

## Limitaties / open items

- `--llm=gemini` is rate-limited — fallback naar ollama-cloud
- Codex via pi is structureel onbetrouwbaar (zie [[forward:pi-cli-non-interactive-blocking-workarounds]])
- Geen multi-reviewer aggregator yet (--wait pickt eerste completed; voor convergence run --list daarna)
- Geen retry-policy bij failed reviews (consume emit verdict=FAILED, caller verantwoordelijk voor herhaal)

## Related

- [[event-bus]] — onderliggende transport
- [[peer-review-v1-deprecated]] — preserved old impl
- `local/reviews/` — archived verdicts
