---
date: 2026-05-31
type: doc
tags: [addons, devbox, planning, agentbrain]
status: active
id: 58ec859e-10ff-5081-9ac3-331c19b123b3
---

# Devbox pilot priorities for add-ons

## Priority order

1. **agentbrain-mcp**
   - Highest value, moderate complexity
   - Clear runtime (`bun`), clear start command, good cross-machine reproducibility target

2. **agent-browser**
   - Good value, moderate complexity
   - Browser automation dependency chain benefits from explicit environment + install flow

3. **youtube-knowledge**
   - High value, higher complexity
   - Sync/transcript pipeline, scheduled runs, more moving parts

4. **voice**
   - High value, highest complexity
   - Audio/STT/TTS toolchains and models are machine-sensitive

## Validation themes

- Reproducibility across machines
- Startup/install simplicity
- Runtime health checks still pass
- Resource usage stays reasonable
- Security posture does not regress

## Minimum validation per pilot

- Clean shell / fresh machine setup path documented
- Start command works from declared environment
- Existing addon health check still passes
- No secret material embedded in dev environment config
- CPU/RAM impact is acceptable when idle and during one representative task
