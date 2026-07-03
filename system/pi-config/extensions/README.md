---
date: 2026-05-18
type: system
tags: [pi, extensions, meta]
id: 0f4faa5d-33ef-5c8f-9369-a9a6bbb4b8ad
---

# Pi Extensions

Custom Pi coding agent extensions. See `extensions.md` for the full catalog and API details.

## Extensions

| Extension               | Purpose                                                 |
| ----------------------- | ------------------------------------------------------- |
| `agentbrain.ts`         | Injects agentBrain context into every session           |
| `session-continuity.ts` | Archives/starts the session journal on Pi session start |
| `extract-learnings.ts`  | Auto-extracts learnings before compaction               |
| `youtube-transcript.ts` | YouTube transcript download tools                       |
| `pi-cloak/`             | Redacts secrets from tool output                        |
| `glm.ts`                | GLM / z.ai provider with keychain fallback              |
| `ollama-cloud.ts`       | Ollama Cloud provider with keychain fallback            |
| `ollama-discovery.ts`   | Local Ollama model discovery provider                   |
| `flow-title.ts`         | Animated gradient session header                        |
| `tps-tracker.ts`        | Live tokens/s display                                   |
| `git-status-widget.ts`  | Git status in Pi sidebar                                |
| `copy-all.ts`           | `/copy-all` command                                     |
| `lg.ts`                 | `/lg` command — git changes summary                     |
| `usage.ts`              | `/usage` command — session usage report                 |
| `git-interceptor.ts`    | Blocks `--no-verify`, prevents editor hangs             |
| `zsh-user-bash.ts`      | Fixes PATH on macOS via zsh login shell                 |
